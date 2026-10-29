// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IERC20Launch {
    function balanceOf(address account) external view returns (uint256);
}

interface ICLLaunchPool {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function liquidity() external view returns (uint128);
    function swap(address recipient, bool zeroForOne, int256 amountSpecified,
                  uint160 sqrtPriceLimitX96, bytes calldata data)
        external returns (int256 amount0, int256 amount1);
}

/// @notice Research reference for ONE preverified V3-compatible pool and ONE purchase.
/// @dev Mock-tested only; not audited or verified against LAPTOP's pre-82 fork state.
///      Does not discover pools, manage EOA nonces, bid, or submit transactions.
contract FixedPoolLaunchBuyer {
    error Unauthorized();
    error BadConfig();
    error AlreadyBought();
    error Closed();
    error NoLiquidity();
    error BadCallback();
    error WrongPayment();
    error TooLittleReceived();
    error TransferFailed();

    address public immutable owner;
    address public immutable pool;
    address public immutable paymentToken;
    address public immutable targetToken;
    address public immutable recipient;
    uint256 public immutable amountIn;
    uint256 public immutable minOut;
    uint64 public immutable openFrom;
    uint64 public immutable openUntil;
    uint160 public immutable sqrtPriceLimitX96;
    bool public immutable zeroForOne;
    mapping(address => bool) public keeper;
    bool public bought;
    bool public cancelled;
    bool private active;
    uint256 private paid;

    event Bought(address indexed trigger, uint256 amountPaid, uint256 amountReceived);
    event Cancelled();

    constructor(address pool_, address expectedFactory_, address payment_, address target_,
                address recipient_, uint256 amountIn_, uint256 minOut_,
                uint64 openFrom_, uint64 openUntil_, uint160 sqrtLimit_,
                address[] memory keepers_) {
        if (pool_.code.length == 0 || payment_.code.length == 0 || target_.code.length == 0
            || recipient_ == address(0) || recipient_ == address(this) || payment_ == target_
            || amountIn_ == 0 || amountIn_ > uint256(type(int256).max) || minOut_ == 0
            || openUntil_ < openFrom_ || keepers_.length == 0) revert BadConfig();
        ICLLaunchPool p = ICLLaunchPool(pool_);
        address t0 = p.token0();
        address t1 = p.token1();
        if (expectedFactory_ == address(0) || p.factory() != expectedFactory_
            || !((t0 == payment_ && t1 == target_) || (t1 == payment_ && t0 == target_))) {
            revert BadConfig();
        }
        if (sqrtLimit_ <= 4295128739 || sqrtLimit_ >= 1461446703485210103287273052203988822378723970342) {
            revert BadConfig();
        }
        owner = msg.sender;
        pool = pool_;
        paymentToken = payment_;
        targetToken = target_;
        recipient = recipient_;
        amountIn = amountIn_;
        minOut = minOut_;
        openFrom = openFrom_;
        openUntil = openUntil_;
        sqrtPriceLimitX96 = sqrtLimit_;
        zeroForOne = t0 == payment_;
        for (uint256 i; i < keepers_.length; ++i) {
            if (keepers_[i] == address(0)) revert BadConfig();
            keeper[keepers_[i]] = true;
        }
    }

    function buy() external returns (uint256 received) {
        if (bought) revert AlreadyBought();
        if (!keeper[msg.sender]) revert Unauthorized();
        if (cancelled || block.timestamp < openFrom || block.timestamp > openUntil) revert Closed();
        // A fast preliminary gate, NOT proof that every token permits transfers.
        if (ICLLaunchPool(pool).liquidity() == 0) revert NoLiquidity();
        uint256 beforeBalance = IERC20Launch(targetToken).balanceOf(recipient);
        bought = true; // Reverts atomically if any later check fails; blocks reentrant buy().
        active = true;
        paid = 0;
        ICLLaunchPool(pool).swap(recipient, zeroForOne, int256(amountIn), sqrtPriceLimitX96, "");
        active = false;
        if (paid != amountIn) revert WrongPayment(); // Reject partial fills in this profile.
        uint256 afterBalance = IERC20Launch(targetToken).balanceOf(recipient);
        if (afterBalance < beforeBalance) revert TooLittleReceived();
        received = afterBalance - beforeBalance;
        if (received < minOut) revert TooLittleReceived();
        emit Bought(msg.sender, paid, received);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        if (msg.sender != pool || !active) revert BadCallback();
        int256 owed = zeroForOne ? amount0Delta : amount1Delta;
        int256 other = zeroForOne ? amount1Delta : amount0Delta;
        if (owed <= 0 || other > 0) revert WrongPayment();
        uint256 due = uint256(owed);
        if (due > amountIn - paid) revert WrongPayment();
        paid += due;
        safeTransfer(paymentToken, pool, due);
    }

    function cancel() external {
        if (msg.sender != owner) revert Unauthorized();
        if (active) revert BadCallback();
        cancelled = true;
        emit Cancelled();
    }

    function rescue(address token, uint256 amount) external {
        if (msg.sender != owner) revert Unauthorized();
        if (active) revert BadCallback();
        safeTransfer(token, owner, amount);
    }

    function safeTransfer(address token, address to, uint256 amount) private {
        if (token.code.length == 0) revert TransferFailed();
        (bool ok, bytes memory result) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        if (!ok || (result.length != 0 && (result.length < 32 || !abi.decode(result, (bool))))) {
            revert TransferFailed();
        }
    }
}
