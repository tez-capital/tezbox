import assert from 'node:assert/strict';
import { waitFor } from './fixture.mjs';

export async function registerTransferTests(t, fixture) {
	await t.test('sends a transaction between bootstrap accounts through Taquito', async () => {
		const fundedBalances = await fixture.ensureFundedBalances();

		await fixture.waitForNextBlock();
		await fixture.sendTransfer();

		const updatedBalances = await waitFor(async () => {
			const { alice, bob } = await fixture.fetchBalances();
			if (bob > fundedBalances.bob) {
				return { alice, bob };
			}
			return false;
		}, 120000, 2000);

		assert(updatedBalances.bob > fundedBalances.bob);
		assert(updatedBalances.alice < fundedBalances.alice);
	});
}
