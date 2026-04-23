import { spawn } from 'node:child_process';
import net from 'node:net';
import { TezosToolkit } from '@taquito/taquito';
import { InMemorySigner } from '@taquito/signer';

export const TEZBOX_IMAGE = process.env.TEZBOX_IMAGE ?? 'tezbox-e2e:current-branch';
export const TEZBOX_USER = 'root';
export const PROTOCOL = 'S';
export const ALICE_SECRET = 'edsk3QoqBuvdamxouPhin7swCvkQNgq4jP5KZPbwWNnwdZpSpJiEbq';
export const ALICE_ADDRESS = 'tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb';
export const BOB_ADDRESS = 'tz1aSkwEot3L2kmUvcoxzjMomb9mvBNuzFK6';

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

export async function waitFor(fn, timeoutMs, intervalMs = 1000) {
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

export class TezboxFixture {
	containerId = undefined;
	rpcUrl = undefined;
	tezos = undefined;
	signer = undefined;
	fundedBalances = undefined;
	fundedLevel = undefined;

	async start() {
		const rpcPort = await reservePort();
		this.rpcUrl = `http://127.0.0.1:${rpcPort}`;

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

		this.containerId = result.stdout.trim();
		this.tezos = new TezosToolkit(this.rpcUrl);

		await waitFor(async () => {
			try {
				const header = await this.tezos.rpc.getBlockHeader();
				return header?.hash;
			} catch {
				return false;
			}
		}, 120000);

		this.signer = await InMemorySigner.fromSecretKey(ALICE_SECRET);
		this.tezos.setProvider({ signer: this.signer });
	}

	async stop() {
		if (!this.containerId) {
			return;
		}

		await run('docker', ['rm', '-f', this.containerId], { allowFailure: true });
	}

	async runCli(args) {
		return run('docker', ['run', '--rm', '--entrypoint', 'tezbox', TEZBOX_IMAGE, ...args]);
	}

	async fetchBalances() {
		const alice = await this.tezos.tz.getBalance(ALICE_ADDRESS);
		const bob = await this.tezos.tz.getBalance(BOB_ADDRESS);
		return { alice, bob };
	}

	async ensureFundedBalances() {
		if (this.fundedBalances) {
			return this.fundedBalances;
		}

		this.fundedBalances = await waitFor(async () => {
			try {
				const { alice, bob } = await this.fetchBalances();
				if (alice > 0n && bob > 0n) {
					return { alice, bob };
				}
			} catch {
				return false;
			}
			return false;
		}, 180000, 2000);
		this.fundedLevel = (await this.tezos.rpc.getBlockHeader()).level;
		return this.fundedBalances;
	}

	async waitForNextBlock() {
		await this.ensureFundedBalances();
		await waitFor(async () => {
			const header = await this.tezos.rpc.getBlockHeader();
			return header.level >= this.fundedLevel + 1 ? header.level : false;
		}, 60000, 1000);
	}

	async sendTransfer() {
		const operation = await this.tezos.wallet.transfer({
			to: BOB_ADDRESS,
			amount: 1,
		}).send();
		await operation.confirmation(1);
		return operation;
	}
}
