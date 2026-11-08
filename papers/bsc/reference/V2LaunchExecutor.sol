// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ILaunchToken {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface ILaunchV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface ILaunchV2Pair {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 timestamp);
}

interface ILaunchV2Router {
    function factory() external view returns (address);
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

/// @notice Executes one successful buy per configured round on a V2-compatible router.
contract V2LaunchExecutor {
    uint256 private constant BPS = 10_000;

    enum State { Idle, Ready, Bought, Sold }

    struct Config {
        address paymentToken;
        address targetToken;
        address router;
        address recipient;
        uint256 maxBuyIn;
        uint256 minPaymentReserve;
        uint256 minBuyOut;
        uint16 maxQuoteShortfallBps;
        uint16 probeBuyBps;
        uint16 probeSellBps;
        bool publicBuy;
    }

    address public owner;
    address public pendingOwner;
    uint256 public roundId;
    uint64 public buyDeadline;
    State public state;

    Config private _config;
    bool private _entered;

    error Unauthorized();
    error ReentrantCall();
    error InvalidConfig();
    error InvalidOwner();
    error RoundMismatch(uint256 expected, uint256 current);
    error WrongState(State required, State current);
    error Expired();
    error PoolNotReady();
    error ReserveTooLow(uint256 actual, uint256 minimum);
    error ZeroAmount();
    error BadQuote();
    error InsufficientOutput(uint256 actual, uint256 minimum);
    error UnexpectedInputDebit();
    error TokenCallFailed(address token);
    error NativeTransferFailed();

    event OwnershipTransferStarted(address indexed owner, address indexed nominee);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RoundOpened(uint256 indexed round, uint64 deadline);
    event RoundCancelled(uint256 indexed round);
    event Probed(uint256 indexed round, uint256 paid, uint256 received, uint256 sold, uint256 recovered);
    event Bought(uint256 indexed round, address indexed caller, address indexed recipient, uint256 paid, uint256 received);
    event Sold(uint256 indexed round, uint256 sold, uint256 received);
    event Withdrawn(address indexed token, address indexed recipient, uint256 amount);

    constructor(address initialOwner) {
        if (initialOwner == address(0) || initialOwner == address(this)) revert InvalidOwner();
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier nonReentrant() {
        if (_entered) revert ReentrantCall();
        _entered = true;
        _;
        _entered = false;
    }

    receive() external payable {}

    function config() external view returns (Config memory) {
        return _config;
    }

    function transferOwnership(address nominee) external onlyOwner nonReentrant {
        if (nominee == address(0) || nominee == address(this)) revert InvalidOwner();
        pendingOwner = nominee;
        emit OwnershipTransferStarted(owner, nominee);
    }

    function acceptOwnership() external nonReentrant {
        if (msg.sender != pendingOwner) revert Unauthorized();
        address previousOwner = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, msg.sender);
    }

    function configure(Config calldata next, uint64 deadline) external onlyOwner nonReentrant returns (uint256) {
        if (
            next.paymentToken == next.targetToken || next.paymentToken.code.length == 0
                || next.targetToken.code.length == 0 || next.router.code.length == 0
                || next.recipient == address(0) || next.maxBuyIn == 0 || next.minBuyOut == 0
                || next.maxQuoteShortfallBps > BPS || next.probeBuyBps >= BPS || next.probeSellBps > BPS
                || (next.probeBuyBps == 0) != (next.probeSellBps == 0)
        ) revert InvalidConfig();
        if (ILaunchV2Router(next.router).factory().code.length == 0) revert InvalidConfig();

        _config = next;
        return _openRound(deadline);
    }

    function init(uint64 deadline) external onlyOwner nonReentrant returns (uint256) {
        if (roundId == 0) revert InvalidConfig();
        return _openRound(deadline);
    }

    function cancelBuy(uint256 expectedRound) external onlyOwner nonReentrant {
        _requireRound(expectedRound, State.Ready);
        state = State.Idle;
        emit RoundCancelled(expectedRound);
    }

    function buy(uint256 expectedRound) external nonReentrant returns (uint256 received) {
        _requireRound(expectedRound, State.Ready);
        Config memory settings = _config;
        if (!settings.publicBuy && msg.sender != owner) revert Unauthorized();
        uint64 deadline = buyDeadline;
        if (block.timestamp > deadline) revert Expired();

        ILaunchV2Router router = ILaunchV2Router(settings.router);
        address[] memory path = _path(settings.paymentToken, settings.targetToken);
        ILaunchV2Pair pair = ILaunchV2Pair(ILaunchV2Factory(router.factory()).getPair(path[0], path[1]));
        if (address(pair).code.length == 0) revert PoolNotReady();
        _checkReserve(pair, path[0], settings.minPaymentReserve);

        uint256 amountIn = _fundedAmount(path[0], settings.maxBuyIn);
        if (settings.probeBuyBps != 0) {
            uint256 probeIn = _portion(amountIn, settings.probeBuyBps);
            _probe(router, path, probeIn, settings.probeSellBps, deadline);
            _checkReserve(pair, path[0], settings.minPaymentReserve);
            amountIn = _fundedAmount(path[0], settings.maxBuyIn - probeIn);
        }

        uint256 minimum = settings.minBuyOut;
        if (settings.maxQuoteShortfallBps < BPS) {
            uint256[] memory quote = router.getAmountsOut(amountIn, path);
            if (quote.length != 2 || quote[0] != amountIn || quote[1] == 0) revert BadQuote();
            uint256 quoteFloor = _portion(quote[1], BPS - settings.maxQuoteShortfallBps);
            if (quoteFloor > minimum) minimum = quoteFloor;
        }

        received = _swap(router, path, settings.recipient, amountIn, minimum, deadline);
        state = State.Bought;
        emit Bought(expectedRound, msg.sender, settings.recipient, amountIn, received);
    }

    function sell(uint256 expectedRound, uint256 minOut, uint256 deadline)
        external onlyOwner nonReentrant returns (uint256 received)
    {
        _requireRound(expectedRound, State.Bought);
        if (block.timestamp > deadline) revert Expired();
        if (minOut == 0) revert ZeroAmount();

        Config memory settings = _config;
        uint256 amountIn = ILaunchToken(settings.targetToken).balanceOf(address(this));
        address[] memory path = _path(settings.targetToken, settings.paymentToken);
        received = _swap(ILaunchV2Router(settings.router), path, address(this), amountIn, minOut, deadline);
        state = State.Sold;
        emit Sold(expectedRound, amountIn, received);
    }

    /// @param amount Use type(uint256).max to withdraw the full token balance.
    function withdrawToken(address token, uint256 amount) external onlyOwner nonReentrant {
        if (amount == type(uint256).max) amount = ILaunchToken(token).balanceOf(address(this));
        if (amount == 0) revert ZeroAmount();
        _tokenCall(token, abi.encodeCall(ILaunchToken.transfer, (owner, amount)));
        emit Withdrawn(token, owner, amount);
    }

    /// @param amount Use type(uint256).max to withdraw the full BNB balance.
    function withdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        if (amount == type(uint256).max) amount = address(this).balance;
        if (amount == 0) revert ZeroAmount();
        (bool ok,) = payable(owner).call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
        emit Withdrawn(address(0), owner, amount);
    }

    function _openRound(uint64 deadline) private returns (uint256) {
        if (block.timestamp > deadline) revert Expired();
        buyDeadline = deadline;
        state = State.Ready;
        ++roundId;
        emit RoundOpened(roundId, deadline);
        return roundId;
    }

    function _requireRound(uint256 expected, State required) private view {
        if (expected != roundId) revert RoundMismatch(expected, roundId);
        if (state != required) revert WrongState(required, state);
    }

    function _checkReserve(ILaunchV2Pair pair, address paymentToken, uint256 minimum) private view {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        if (reserve0 == 0 || reserve1 == 0) revert PoolNotReady();
        uint256 paymentReserve = pair.token0() == paymentToken ? reserve0 : reserve1;
        if (paymentReserve < minimum) revert ReserveTooLow(paymentReserve, minimum);
    }

    function _fundedAmount(address token, uint256 cap) private view returns (uint256) {
        uint256 balance = ILaunchToken(token).balanceOf(address(this));
        if (balance == 0) revert ZeroAmount();
        return balance < cap ? balance : cap;
    }

    function _probe(
        ILaunchV2Router router,
        address[] memory path,
        uint256 amountIn,
        uint16 sellBps,
        uint64 deadline
    ) private {
        uint256 bought = _swap(router, path, address(this), amountIn, 1, deadline);
        uint256 sellAmount = _portion(bought, sellBps);
        uint256 recovered = _swap(router, _path(path[1], path[0]), address(this), sellAmount, 1, deadline);
        emit Probed(roundId, amountIn, bought, sellAmount, recovered);
    }

    function _swap(
        ILaunchV2Router router,
        address[] memory path,
        address recipient,
        uint256 amountIn,
        uint256 minOut,
        uint256 deadline
    ) private returns (uint256 received) {
        if (amountIn == 0) revert ZeroAmount();
        ILaunchToken input = ILaunchToken(path[0]);
        ILaunchToken output = ILaunchToken(path[1]);
        uint256 inputBefore = input.balanceOf(address(this));
        if (inputBefore < amountIn) revert UnexpectedInputDebit();
        uint256 outputBefore = output.balanceOf(recipient);

        // Each swap starts and ends with zero allowance outside its exact input approval.
        _tokenCall(path[0], abi.encodeCall(ILaunchToken.approve, (address(router), amountIn)));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, minOut, path, recipient, deadline);
        _tokenCall(path[0], abi.encodeCall(ILaunchToken.approve, (address(router), 0)));

        if (input.balanceOf(address(this)) != inputBefore - amountIn) revert UnexpectedInputDebit();
        uint256 outputAfter = output.balanceOf(recipient);
        received = outputAfter > outputBefore ? outputAfter - outputBefore : 0;
        if (received < minOut) revert InsufficientOutput(received, minOut);
    }

    function _tokenCall(address token, bytes memory data) private {
        if (token.code.length == 0) revert TokenCallFailed(token);
        (bool ok, bytes memory result) = token.call(data);
        if (!ok || (result.length != 0 && (result.length != 32 || !abi.decode(result, (bool))))) {
            revert TokenCallFailed(token);
        }
    }

    function _path(address tokenIn, address tokenOut) private pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }

    function _portion(uint256 amount, uint256 bps) private pure returns (uint256) {
        return (amount / BPS) * bps + (amount % BPS) * bps / BPS;
    }
}
