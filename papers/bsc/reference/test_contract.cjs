const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const solc = require('solc');
const ganache = require('ganache');
const { BrowserProvider, Contract, ContractFactory, MaxUint256, ZeroAddress } = require('ethers');

assert.match(solc.version(), /^0\.8\.30\+/);
const sources = Object.fromEntries(['V2LaunchExecutor.sol', 'MockV2.sol'].map(name => [
    name,
    { content: fs.readFileSync(path.join(__dirname, name), 'utf8') },
]));
const compiled = JSON.parse(solc.compile(JSON.stringify({
    language: 'Solidity',
    sources,
    settings: {
        evmVersion: 'paris',
        optimizer: { enabled: true, runs: 200 },
        outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object'] } },
    },
})));
const errors = (compiled.errors ?? []).filter(item => item.severity === 'error');
assert.equal(errors.length, 0, errors.map(item => item.formattedMessage).join('\n'));
const artifacts = { ...compiled.contracts['V2LaunchExecutor.sol'], ...compiled.contracts['MockV2.sol'] };
const gas = { gasLimit: 1_000_000 };

async function send(pending) {
    return (await pending).wait();
}

function rejectsWith(pending, name) {
    return assert.rejects(pending, error => error.code === 'CALL_EXCEPTION' && error.revert?.name === name);
}

function minedRevert(pending) {
    return assert.rejects(() => send(pending), error => error.receipt?.status === 0);
}

function event(contract, receipt, name) {
    const log = receipt.logs
        .filter(item => item.address === contract.target)
        .map(item => contract.interface.parseLog(item))
        .find(item => item?.name === name);
    assert.ok(log, `missing ${name}`);
    return log.args;
}

async function fixture(t, { makePool = true, paymentReserve = 1_000_000n } = {}) {
    const chain = ganache.provider({
        logging: { quiet: true },
        chain: { chainId: 31337, hardfork: 'shanghai' },
        wallet: { totalAccounts: 4, deterministic: true },
    });
    t.after(() => chain.disconnect());
    const provider = new BrowserProvider(chain, undefined, { cacheTimeout: -1 });
    const [owner, other, recipient, secondTrigger] = await Promise.all([0, 1, 2, 3].map(i => provider.getSigner(i)));
    const deploy = async (name, args = []) => {
        const artifact = artifacts[name];
        const instance = await new ContractFactory(artifact.abi, artifact.evm.bytecode.object, owner).deploy(...args);
        return instance.waitForDeployment();
    };
    const payment = await deploy('MockToken');
    const target = await deploy('MockToken');
    const router = await deploy('MockV2Router');
    const executor = await deploy('V2LaunchExecutor', [owner.address]);
    const funded = 180_000n;
    await send(payment.mint(executor.target, funded));
    const tokens = [payment.target, target.target];
    const createPair = async () => {
        await send(router.createPair(...tokens));
        return new Contract(await router.getPair(...tokens), artifacts.MockV2Pair.abi, owner);
    };
    let pair;
    if (makePool) {
        pair = await createPair();
        await send(payment.mint(pair.target, paymentReserve));
        await send(target.mint(pair.target, 2_000_000n));
        await send(pair.sync());
    }
    const getTimestamp = async () => BigInt((await chain.request({
        method: 'eth_getBlockByNumber', params: ['latest', false],
    })).timestamp);
    const deadline = (await getTimestamp()) + 600n;
    const config = {
        paymentToken: payment.target,
        targetToken: target.target,
        router: router.target,
        recipient: recipient.address,
        maxBuyIn: 100_000n,
        minPaymentReserve: 1_000n,
        minBuyOut: 1n,
        maxQuoteShortfallBps: 10_000,
        probeBuyBps: 0,
        probeSellBps: 0,
        publicBuy: false,
    };
    const configure = async (changes = {}) => {
        await send(executor.configure({ ...config, ...changes }, deadline));
        return executor.roundId();
    };
    return {
        chain, owner, other, recipient, secondTrigger, payment, target, router, executor,
        config, configure, pair, createPair, deadline, tokens, funded,
    };
}

test('configuration can precede pool creation and owner controls private rounds', async t => {
    const { executor, other, config, configure, createPair, deadline } = await fixture(t, { makePool: false });
    await rejectsWith(executor.init.staticCall(deadline), 'InvalidConfig');
    await rejectsWith(executor.connect(other).configure.staticCall(config, deadline), 'Unauthorized');
    await rejectsWith(executor.configure.staticCall({ ...config, minBuyOut: 0n }, deadline), 'InvalidConfig');
    await rejectsWith(executor.configure.staticCall({ ...config, probeBuyBps: 100 }, deadline), 'InvalidConfig');
    await rejectsWith(executor.configure.staticCall({ ...config, maxQuoteShortfallBps: 10_001 }, deadline), 'InvalidConfig');
    const round = await configure();
    await rejectsWith(executor.connect(other).buy.staticCall(round), 'Unauthorized');
    await rejectsWith(executor.buy.staticCall(round), 'PoolNotReady');
    await createPair();
    await rejectsWith(executor.buy.staticCall(round), 'PoolNotReady');
    assert.equal(await executor.state(), 1n);
});

test('competing public triggers execute once and pay the configured recipient', async t => {
    const { executor, other, secondTrigger, recipient, payment, target, router, config, configure, funded } = await fixture(t);
    const round = await configure({ publicBuy: true });
    const data = executor.interface.encodeFunctionData('buy', [round]);
    await send(router.setBehavior(false, false, data));

    const results = await Promise.allSettled([
        send(executor.connect(other).buy(round, gas)),
        send(executor.connect(secondTrigger).buy(round, gas)),
    ]);
    const [winner] = results.filter(item => item.status === 'fulfilled');
    assert.equal(results.filter(item => item.status === 'fulfilled').length, 1);
    assert.equal(results.find(item => item.status === 'rejected').reason.receipt.status, 0);
    const bought = event(executor, winner.value, 'Bought');
    assert.equal(bought.recipient, recipient.address);
    assert.equal(bought.paid, config.maxBuyIn);
    assert.equal(await target.balanceOf(recipient.address), bought.received);
    assert.equal(await target.balanceOf(bought.caller), 0n);
    assert.equal(await payment.balanceOf(executor.target), funded - config.maxBuyIn);
    assert.equal(await payment.allowance(executor.target, router.target), 0n);
    assert.equal(await router.rejectedReentry(), true);
    assert.equal(await executor.state(), 2n);
});

test('reserve minimum uses synced payment reserves', async t => {
    const { executor, payment, pair, configure } = await fixture(t, { paymentReserve: 500n });
    const round = await configure();
    await send(payment.mint(pair.target, 1_500n));
    await rejectsWith(executor.buy.staticCall(round), 'ReserveTooLow');
    await send(pair.sync());
    await send(executor.buy(round, gas));
    assert.equal(await executor.state(), 2n);
});

test('fee-on-transfer settlement enforces the quote floor and rolls back failed trades', async t => {
    const { executor, target, payment, recipient, router, pair, tokens, config, configure, funded } = await fixture(t);
    await send(payment.setBehavior(200, ZeroAddress, false));
    await send(target.setBehavior(1_000, ZeroAddress, false));
    await send(router.setBehavior(true, false, '0x'));
    const round = await configure({ maxQuoteShortfallBps: 500 });
    const before = await pair.getReserves();
    await rejectsWith(executor.buy.staticCall(round), 'InsufficientOutput');
    await minedRevert(executor.buy(round, gas));
    assert.equal(await executor.state(), 1n);
    assert.equal(await payment.balanceOf(executor.target), funded);
    assert.equal(await target.balanceOf(recipient.address), 0n);
    assert.equal(await payment.allowance(executor.target, router.target), 0n);
    assert.deepEqual(Array.from((await pair.getReserves()).slice(0, 2)), Array.from(before.slice(0, 2)));

    await send(router.setBehavior(false, false, '0x'));
    const next = await configure({ maxQuoteShortfallBps: 2_000 });
    const [, grossOut] = await router.getAmountsOut(config.maxBuyIn * 98n / 100n, tokens);
    const expectedOut = grossOut - grossOut / 10n;
    const bought = event(executor, await send(executor.buy(next, gas)), 'Bought');
    assert.equal(bought.received, expectedOut);
    assert.equal(await target.balanceOf(recipient.address), expectedOut);
});

test('swap verifies the actual payment debit and an absolute minimum', async t => {
    const { executor, router, configure } = await fixture(t);
    await send(router.setBehavior(true, false, '0x'));
    let round = await configure({ minBuyOut: 2_000_001n });
    await rejectsWith(executor.buy.staticCall(round), 'InsufficientOutput');
    await send(router.setBehavior(false, true, '0x'));
    round = await configure();
    await rejectsWith(executor.buy.staticCall(round), 'UnexpectedInputDebit');
});

test('a blocked probe sell rolls back and the probe sells only newly received tokens', async t => {
    const { executor, pair, recipient, payment, target, router, config, configure, funded } = await fixture(t);
    const oldInventory = 5_000n;
    await send(target.mint(executor.target, oldInventory));
    await send(payment.setBehavior(0, ZeroAddress, true));
    await send(target.setBehavior(0, pair.target, true));
    const round = await configure({ probeBuyBps: 100, probeSellBps: 5_000 });
    await minedRevert(executor.buy(round, gas));
    assert.equal(await payment.balanceOf(executor.target), funded);
    assert.equal(await target.balanceOf(executor.target), oldInventory);
    assert.equal(await target.balanceOf(recipient.address), 0n);
    assert.equal(await executor.state(), 1n);
    assert.equal(await payment.allowance(executor.target, router.target), 0n);
    assert.equal(await target.allowance(executor.target, router.target), 0n);

    await send(target.setBehavior(0, ZeroAddress, true));
    const receipt = await send(executor.buy(round, gas));
    const probed = event(executor, receipt, 'Probed');
    const bought = event(executor, receipt, 'Bought');
    assert.equal(probed.paid, config.maxBuyIn / 100n);
    assert.equal(probed.sold, probed.received / 2n);
    assert.ok(probed.recovered > 0n);
    assert.equal(probed.paid + bought.paid, config.maxBuyIn);
    assert.equal(await target.balanceOf(executor.target), oldInventory + probed.received - probed.sold);
    assert.equal(await payment.balanceOf(executor.target), funded - config.maxBuyIn + probed.recovered);
    assert.equal(await target.balanceOf(recipient.address), bought.received);
    assert.equal(await payment.allowance(executor.target, router.target), 0n);
    assert.equal(await target.allowance(executor.target, router.target), 0n);
});

test('owner sells custodied tokens once and receives actual payment proceeds', async t => {
    const { executor, other, payment, target, router, configure, deadline } = await fixture(t);
    const round = await configure({ recipient: executor.target });
    await rejectsWith(executor.sell.staticCall(round, 1n, deadline), 'WrongState');
    await send(executor.buy(round, gas));
    await rejectsWith(executor.connect(other).sell.staticCall(round, 1n, deadline), 'Unauthorized');
    const inventory = await target.balanceOf(executor.target);
    const before = await payment.balanceOf(executor.target);
    await send(router.setBehavior(true, false, '0x'));
    await rejectsWith(executor.sell.staticCall(round, 1_200_001n, deadline), 'InsufficientOutput');
    const sold = event(executor, await send(executor.sell(round, 1n, deadline, gas)), 'Sold');
    assert.equal(sold.sold, inventory);
    assert.equal(await target.balanceOf(executor.target), 0n);
    assert.equal(await target.allowance(executor.target, router.target), 0n);
    assert.equal(await payment.balanceOf(executor.target) - before, sold.received);
    assert.equal(await executor.state(), 3n);
    await rejectsWith(executor.sell.staticCall(round, 1n, deadline), 'WrongState');
});

test('cancel, rearm and expiry prevent execution with stale rounds', async t => {
    const { executor, other, chain, configure, deadline } = await fixture(t);
    const round = await configure({ publicBuy: true });
    await send(executor.cancelBuy(round));
    await rejectsWith(executor.connect(other).buy.staticCall(round), 'WrongState');
    await send(executor.init(deadline));
    const next = await executor.roundId();
    assert.equal(next, round + 1n);
    await rejectsWith(executor.connect(other).buy.staticCall(round), 'RoundMismatch');
    await rejectsWith(executor.cancelBuy.staticCall(round), 'RoundMismatch');
    await chain.request({ method: 'evm_increaseTime', params: [601] });
    await chain.request({ method: 'evm_mine', params: [] });
    await rejectsWith(executor.connect(other).buy.staticCall(next), 'Expired');
});

test('two-step ownership controls partial and full token and BNB withdrawals', async t => {
    const { executor, chain, owner, other, recipient, payment, funded } = await fixture(t);
    await send(owner.sendTransaction({ to: executor.target, value: 100n }));
    await rejectsWith(executor.connect(other).withdrawToken.staticCall(payment.target, 1n), 'Unauthorized');
    await send(executor.transferOwnership(other.address));
    assert.equal(await executor.owner(), owner.address);
    await rejectsWith(executor.connect(recipient).acceptOwnership.staticCall(), 'Unauthorized');
    await send(executor.connect(other).acceptOwnership());
    const controlled = executor.connect(other);
    await rejectsWith(executor.withdrawBNB.staticCall(1n), 'Unauthorized');
    await send(controlled.withdrawToken(payment.target, 23n));
    assert.equal(await payment.balanceOf(other.address), 23n);
    await send(controlled.withdrawToken(payment.target, MaxUint256));
    assert.equal(await payment.balanceOf(other.address), funded);
    await send(controlled.withdrawBNB(30n));
    const balance = async () => BigInt(await chain.request({ method: 'eth_getBalance', params: [executor.target, 'latest'] }));
    assert.equal(await balance(), 70n);
    await send(controlled.withdrawBNB(MaxUint256));
    assert.equal(await balance(), 0n);
});
