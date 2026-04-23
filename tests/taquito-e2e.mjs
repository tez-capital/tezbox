import { after, before, test } from 'node:test';
import { TezboxFixture } from './e2e/fixture.mjs';
import { registerCliTests } from './e2e/cli.mjs';
import { registerRpcTests } from './e2e/rpc.mjs';
import { registerTransferTests } from './e2e/transfers.mjs';

const fixture = new TezboxFixture();

before(async () => fixture.start());
after(async () => fixture.stop());

test('runs starter Taquito e2e coverage against a TezBox container', async (t) => {
	await registerCliTests(t, fixture);
	await registerRpcTests(t, fixture);
	await registerTransferTests(t, fixture);
});
