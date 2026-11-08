// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public feeBps;
    address public blockedRecipient;
    bool public omitApproveReturn;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function setBehavior(uint256 fee, address blocked, bool omitReturn) external {
        feeBps = fee;
        blockedRecipient = blocked;
        omitApproveReturn = omitReturn;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        require(amount == 0 || allowance[msg.sender][spender] == 0, "reset allowance");
        allowance[msg.sender][spender] = amount;
        if (omitApproveReturn) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(to != blockedRecipient, "blocked transfer");
        balanceOf[from] -= amount;
        balanceOf[to] += amount - (amount * feeBps / 10_000);
    }
}

contract MockV2Pair {
    address public immutable token0;
    address public immutable token1;
    address public immutable router;
    uint112 private _reserve0;
    uint112 private _reserve1;

    constructor(address tokenA, address tokenB) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        router = msg.sender;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (_reserve0, _reserve1, uint32(block.timestamp));
    }

    function sync() public {
        _reserve0 = uint112(MockToken(token0).balanceOf(address(this)));
        _reserve1 = uint112(MockToken(token1).balanceOf(address(this)));
    }

    function pay(address token, address to, uint256 amount) external {
        require(msg.sender == router, "router");
        require(MockToken(token).transfer(to, amount));
        sync();
    }
}

contract MockV2Router {
    mapping(address => mapping(address => address)) public getPair;
    bool public ignoreMinimum;
    bool public underpull;
    bytes private _reentryData;
    bool public rejectedReentry;

    function factory() external view returns (address) {
        return address(this);
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(getPair[tokenA][tokenB] == address(0), "pair exists");
        pair = address(new MockV2Pair(tokenA, tokenB));
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
    }

    function setBehavior(bool ignoreMin, bool pullLess, bytes calldata reentryData) external {
        ignoreMinimum = ignoreMin;
        underpull = pullLess;
        _reentryData = reentryData;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts) {
        (uint256 reserveIn, uint256 reserveOut) = _reserves(path);
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = _quote(amountIn, reserveIn, reserveOut);
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 minOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        require(block.timestamp <= deadline, "deadline");
        MockToken output = MockToken(path[1]);
        uint256 beforeOut = output.balanceOf(to);
        _swap(amountIn, path, to);
        require(ignoreMinimum || output.balanceOf(to) - beforeOut >= minOut, "router minOut");
    }

    function _swap(uint256 amountIn, address[] calldata path, address to) private {
        MockV2Pair pair = MockV2Pair(getPair[path[0]][path[1]]);
        (uint256 reserveIn, uint256 reserveOut) = _reserves(path);
        MockToken input = MockToken(path[0]);
        require(input.transferFrom(msg.sender, address(pair), underpull ? amountIn - 1 : amountIn));
        if (_reentryData.length != 0) {
            (bool ok, bytes memory data) = msg.sender.call(_reentryData);
            require(!ok && bytes4(data) == bytes4(keccak256("ReentrantCall()")), "unexpected callback result");
            rejectedReentry = true;
        }
        uint256 receivedByPair = input.balanceOf(address(pair)) - reserveIn;
        pair.pay(path[1], to, _quote(receivedByPair, reserveIn, reserveOut));
    }

    function _reserves(address[] calldata path) private view returns (uint256, uint256) {
        MockV2Pair pair = MockV2Pair(getPair[path[0]][path[1]]);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        return pair.token0() == path[0] ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function _quote(uint256 amount, uint256 reserveIn, uint256 reserveOut) private pure returns (uint256) {
        require(amount > 0 && reserveIn > 0 && reserveOut > 0, "quote");
        uint256 netInput = amount * 9_975;
        return netInput * reserveOut / (reserveIn * 10_000 + netInput);
    }
}
