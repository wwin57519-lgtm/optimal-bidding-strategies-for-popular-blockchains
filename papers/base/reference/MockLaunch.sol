// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface ICallbackMock {
    function uniswapV3SwapCallback(int256, int256, bytes calldata) external;
}

contract MockToken {
    mapping(address => uint256) public balanceOf;
    uint256 public taxBps;
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function setTax(uint256 bps) external { taxBps = bps; }
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "BAL");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount * (10000 - taxBps) / 10000;
        return true;
    }
}

contract MockPool {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint128 public liquidity;
    uint256 public outputAmount = 1200 ether;
    uint256 public paymentBps = 10000;
    constructor(address factory_, address token0_, address token1_) {
        factory = factory_; token0 = token0_; token1 = token1_;
    }
    function setLiquidity(uint128 value) external { liquidity = value; }
    function setOutput(uint256 value) external { outputAmount = value; }
    function setPaymentBps(uint256 value) external { paymentBps = value; }
    function swap(address recipient, bool zeroForOne, int256 amount, uint160, bytes calldata data)
        external returns (int256 amount0, int256 amount1) {
        require(liquidity > 0 && amount > 0, "STATE");
        uint256 due = uint256(amount) * paymentBps / 10000;
        address tokenIn = zeroForOne ? token0 : token1;
        address tokenOut = zeroForOne ? token1 : token0;
        uint256 beforeBalance = MockToken(tokenIn).balanceOf(address(this));
        MockToken(tokenOut).transfer(recipient, outputAmount);
        amount0 = zeroForOne ? int256(due) : -int256(outputAmount);
        amount1 = zeroForOne ? -int256(outputAmount) : int256(due);
        ICallbackMock(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
        require(MockToken(tokenIn).balanceOf(address(this)) == beforeBalance + due, "PAYMENT");
    }
}
