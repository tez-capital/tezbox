import assert from 'node:assert/strict';

export async function registerCliTests(t, fixture) {
	await t.test('lists the bundled protocols from the branch-built image', async () => {
		const { stdout } = await fixture.runCli(['list-protocols']);

		assert.match(stdout, /(PtSeouLo|\bS\b)/);
		assert.match(stdout, /(PtTALLiN|\bT\b)/);
	});
}
