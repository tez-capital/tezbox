background20<p align="center"><img width="150" src="https://raw.githubusercontent.com/tez-capital/tezbox/main/assets/logo.svg" alt="TEZBOX logo"></p>

<h2 align="center" class="heading-element">TEZBOX - tezos sandbox by tez.capital</h2>

### What is TezBox?

TezBox is a tezos sandbox that allows you to run a minimal local tezos chain with a single command. It is designed to be a simple and easy to use tool for developers who want to quickly test their smart contracts or dapps on a local tezos chain.

⚠️⚠️⚠️ BREAKING 0.3.0 ⚠️⚠️⚠️

- output of services is not logged into console. See [Logs](#logs) section for more details.
- each baker runs as separate process

### How to use TezBox?

To use TezBox, you need to have OCI compatible container runtime installed on your machine (e.g. docker, podman...). You can run TezBox with the following command:

```bash
# to run chain with the PsParisC protocol
docker run -it -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v20.3 parisbox
# or to run in the background
docker run -d -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v20.3 parisbox
```

You can list available protocols with the following command:
```bash
# docker run -it <image> list-protocols
docker run -it --entrypoint tezbox ghcr.io/tez-capital/tezbox:tezos-v20.3 list-protocols
```
#### Qena & Quebec

##### Qena
```bash
# to run chain with the PsParisC protocol
docker run -it -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v21.0-rc3 qenabox
# or to run in the background
docker run -d -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v21.0-rc3 qenabox
```
##### Quebec A
```bash
# to run chain with the PsParisC protocol
docker run -it -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v21.0-rc1 quebecbox
# or to run in the background
docker run -d -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v21.0-rc1 quebecbox
```
##### Quebec B
```bash
# to run chain with the PsParisC protocol
docker run -it -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v21.0-rc2 quebecbox
# or to run in the background
docker run -d -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v21.0-rc2 quebecbox
```

#### Logs

Output from each service are stored in /ascend/logs within the container. To access the logs without entering the container, mount this directory from outside the container.

#### Dal

To run a dal within tezbox start tezbox with `--with-dal` option as follows:

```bash
# to run chain with the PsParisC protocol
docker run -it -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v20.3 parisbox --with-dal
# or to run in the background
docker run -d -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v20.3 parisbox --with-dal
```

### Configuration

All configuration files are located in the `/tezbox/configuration` directory and merged with overrides from `/tezbox/overrides` directory. 

NOTE: *It is not possible to define bootstrap_accounts through sandbox-parameters. Use `.../configuration/bakers.hjson` instead.*

#### Overrides and Configuration through mounted volumes

You can override any configuration file by mounting your own file to the `/tezbox/overrides` directory. The file will be merged with the default configuration. If you want to replace the whole configuration or file without merging, you can mount it to the `/tezbox/configuration` directory. The configuration is merged with the overrides and the result is stored in the `/tezbox/context` directory during the initialization of the container. **Array values are always replaced, not concatenated.**

For example if you want to adjust block times, you can create `sandbox-override-parameters.hjson` file with the following content:
```hjson
minimal_block_delay: "1" // minimal block delay in seconds, has to be quoted
```
and run the container with the following command:
```bash
# docker run -it -v <path-to-your-file>:/tezbox/overrides/protocols/<case sensitive protocol id>/sandbox-parameters.hjson ... ghcr.io/tez-capital/tezbox:tezos-v20.3 oxfordbox
docker run -it -v $(pwd)/sandbox-override-parameters.hjson:/tezbox/overrides/protocols/Proxford/sandbox-parameters.hjson ... ghcr.io/tez-capital/tezbox:tezos-v20.3 oxfordbox
```
You can determine path based on folder structure in [configuration directory](https://github.com/tez-capital/tezbox/tree/main/configuration).

Optionally you can mount entire overrides/configuration directory to `/tezbox/overrides` or `/tezbox/configuration` to replace the whole configuration.

```bash
docker run -it -v <path-to-your-configuration-overrides>:/tezbox/overrides ... ghcr.io/tez-capital/tezbox:tezos-v20.3 oxfordbox
```

NOTE: **Do not edit or mount configuration files in the `/tezbox/context` directory. They are generated automatically and should not be modified manually.**

#### Accounts

By default tezbox comes with these accounts: 
```yaml
{
    alice: {
        pkh: tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb
        pk: edpkvGfYw3LyB1UcCahKQk4rF2tvbMUk8GFiTuMjL75uGXrpvKXhjn
        sk: unencrypted:edsk3QoqBuvdamxouPhin7swCvkQNgq4jP5KZPbwWNnwdZpSpJiEbq
        balance: 2000000
    }
    bob: {
        pkh: tz1aSkwEot3L2kmUvcoxzjMomb9mvBNuzFK6
        pk: edpkurPsQ8eUApnLUJ9ZPDvu98E8VNj4KtJa1aZr16Cr5ow5VHKnz4
        sk: unencrypted:edsk3RFfvaFaxbHx8BMtEW1rKQcPtDML3LXjNqMNLCzC3wLC1bWbAt
        balance: 2000000
    }
}
```
You can add modify as needed. Just mount your own file to `/tezbox/overrides/accounts.hjson` for override or `/tezbox/configuration/accounts.hjson` for full replacement.

#### Services

You can adjust service behavior by mounting your own configuration to `/tezbox/overrides/services/...` for override or `/tezbox/configuration/services/...` for full replacement.

If you want to disable a service, you can create override with `autostart: false`. For example to disable baker service you would crease `baker.hjson` file:
```hjson
autostart: false
```
and mount it into overrides directory:
```bash
docker run -it -v $(pwd)/baker.hjson:/tezbox/overrides/services/baker.hjson ... ghcr.io/tez-capital/tezbox:tezos-v20.3 oxfordbox
```

#### Chain Context

Chain and protocol is automatically initialized only once during the first run. The chain and all runtime data are stored in `/tezbox/data` directory. If you want to persist your sandbox state just run it with mounted volume to `/tezbox/data` directory.

e.g.
```bash
docker run -it -v $(pwd)/sandbox-data:/tezbox -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v20.3 oxfordbox
```

NOTE: *To reset the state you can remove the `/tezbox/data/tezbox-initialized` file. After its removal all chain and client data will be removed and the chain will be reinitialized on the next run.*

#### Flextesa Compatibility

To maintain some level of compatibility with flextesa, the alice and bob accounts are the same. The RPC port is exposed on ports 8732 and 20000. And we use similar protocol aliases like oxfordbox and parisbox.

But unlike flextesa the tezbox won't expose configuration through command line arguments. Instead, you can edit configuration directly in the configuration files or use overrides.

### Building TezBox

To build TezBox follow these steps:

1. clone the repository
   - `git clone https://github.com/tez-capital/tezbox && cd tezbox`
2. edit the Dockerfile, configuration and sources if needed
3. build lua sources (you can get eli [here](https://github.com/alis-is/eli/releases))
   - `eli build/build.lua`
4. build the image
   - `docker build --build-arg="PROTOCOLS=PsParisC" --build-arg="IMAGE_TAG=octez-v20.3" -t tezbox . -f  containers/tezos/Containerfile --no-cache`

### Future development

TezBox is going to follow official octez releases and tag. You can expect new release shortly after the official release of the new octez version.

We would like to introduce tezbox minimal image with only the octez node, baker, client and the minimal configuration eventually. But there is no ETA for this feature yet.