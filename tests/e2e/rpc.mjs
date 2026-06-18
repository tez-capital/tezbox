import assert from 'node:assert/strict';
import { ALICE_ADDRESS } from './fixture.mjs';

export async function registerRpcTests(t, fixture) {
	await t.test('creates a Taquito wallet from a sandbox secret key', async () => {
		const aliceAddress = await fixture.signer.publicKeyHash();
		assert.equal(aliceAddress, ALICE_ADDRESS);
	});

	await t.test('serves chain metadata from the sandbox RPC', async () => {
		const chainId = await fixture.tezos.rpc.getChainId();
		const header = await fixture.tezos.rpc.getBlockHeader();

		assert.equal(typeof chainId, 'string');
		assert(chainId.length > 0);
		assert.equal(typeof header.hash, 'string');
		assert(header.hash.length > 0);
		assert(header.level >= 0);
	});

	await t.test('reads funded bootstrap balances from the container RPC', async () => {
		const fundedBalances = await fixture.ensureFundedBalances();

		assert(fundedBalances.alice > 0n);
		assert(fundedBalances.bob > 0n);
	});
}
