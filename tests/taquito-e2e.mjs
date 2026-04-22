import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { spawn } from 'node:child_process';
import net from 'node:net';
import { TezosToolkit } from '@taquito/taquito';
import { InMemorySigner } from '@taquito/signer';

const TEZBOX_IMAGE = 'ghcr.io/tez-capital/tezbox:tezos-v24.4';
const TEZBOX_USER = 'root';
const PROTOCOL = 'S';
const ALICE_SECRET = 'edsk3QoqBuvdamxouPhin7swCvkQNgq4jP5KZPbwWNnwdZpSpJiEbq';
const ALICE_ADDRESS = 'tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb';
const BOB_ADDRESS = 'tz1aSkwEot3L2kmUvcoxzjMomb9mvBNuzFK6';

let containerId;
let rpcUrl;
let tezos;
let signer;
let fundedBalances;

function run(command, args, options = {}) {
	return new Promise((resolve, reject) => {
		const { allowFailure, stdout: stdoutMode, stderr: stderrMode, ...spawnOptions } = options;
		const child = spawn(command, args, {
			stdio: ['ignore', 'pipe', 'pipe'],
			...spawnOptions,
		});

		let stdout = '';
		let stderr = '';

		child.stdout.on('data', (data) => {
			const text = data.toString();
			stdout += text;
			if (stdoutMode === 'inherit') {
				process.stdout.write(text);
			}
		});

		child.stderr.on('data', (data) => {
			const text = data.toString();
			stderr += text;
			if (stderrMode === 'inherit') {
				process.stderr.write(text);
			}
		});

		child.on('error', reject);
		child.on('close', (code) => {
			if (code !== 0 && !allowFailure) {
				reject(new Error(`${command} ${args.join(' ')} failed with exit code ${code}\n${stderr || stdout}`));
				return;
			}
			resolve({ code, stdout, stderr });
		});
	});
}

async function reservePort() {
	return new Promise((resolve, reject) => {
		const server = net.createServer();
		server.unref();
		server.on('error', reject);
		server.listen(0, '127.0.0.1', () => {
			const { port } = server.address();
			server.close((error) => {
				if (error) {
					reject(error);
					return;
				}
				resolve(port);
			});
		});
	});
}

async function waitFor(fn, timeoutMs, intervalMs = 1000) {
	const deadline = Date.now() + timeoutMs;
	while (Date.now() < deadline) {
		const value = await fn();
		if (value) {
			return value;
		}
		await new Promise((resolve) => setTimeout(resolve, intervalMs));
	}
	throw new Error('Timed out waiting for TezBox container readiness');
}

async function fetchBalances() {
	const alice = await tezos.tz.getBalance(ALICE_ADDRESS);
	const bob = await tezos.tz.getBalance(BOB_ADDRESS);
	return { alice, bob };
}

async function sendTransfer() {
	const operation = await tezos.wallet.transfer({
		to: BOB_ADDRESS,
		amount: 1,
	}).send();
	await operation.confirmation(1);
	return operation;
}

before(async () => {
	const rpcPort = await reservePort();
	rpcUrl = `http://127.0.0.1:${rpcPort}`;

	const result = await run('docker', [
		'run',
		'-d',
		'-p',
		`127.0.0.1:${rpcPort}:8732`,
		'-e',
		`TEZBOX_USER=${TEZBOX_USER}`,
		TEZBOX_IMAGE,
		PROTOCOL,
	]);

	containerId = result.stdout.trim();
	tezos = new TezosToolkit(rpcUrl);

	await waitFor(async () => {
		try {
			const header = await tezos.rpc.getBlockHeader();
			return header?.hash;
		} catch {
			return false;
		}
	}, 120000);

	signer = await InMemorySigner.fromSecretKey(ALICE_SECRET);
	tezos.setProvider({ signer });
});

after(async () => {
	if (!containerId) {
		return;
	}

	await run('docker', ['rm', '-f', containerId], { allowFailure: true });
});

test('runs starter Taquito e2e coverage against a TezBox container', async (t) => {
	await t.test('creates a Taquito wallet from a sandbox secret key', async () => {
		const aliceAddress = await signer.publicKeyHash();
		assert.equal(aliceAddress, ALICE_ADDRESS);
	});

	await t.test('reads funded bootstrap balances from the container RPC', async () => {
		fundedBalances = await waitFor(async () => {
			try {
				const { alice, bob } = await fetchBalances();
				if (alice > 0n && bob > 0n) {
					return { alice, bob };
				}
			} catch {
				return false;
			}
			return false;
		}, 180000, 2000);

		assert(fundedBalances.alice > 0n);
		assert(fundedBalances.bob > 0n);
	});

	await t.test('sends a transaction between bootstrap accounts through Taquito', async () => {
		assert(fundedBalances, 'expected balances to be loaded before transfer test');

		await sendTransfer();

		let updatedBalances = await waitFor(fetchBalances, 30000, 2000);

		if (updatedBalances.bob <= fundedBalances.bob) {
			await sendTransfer();
			updatedBalances = await waitFor(async () => {
				const { alice, bob } = await fetchBalances();
				if (bob > fundedBalances.bob) {
					return { alice, bob };
				}
				return false;
			}, 120000, 2000);
		}

		assert(updatedBalances.bob > fundedBalances.bob);
		assert(updatedBalances.alice < fundedBalances.alice);
	});
});
