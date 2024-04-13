## TEZBOX - tezos sandbox by tez.capital

### What is TezBox?

TezBox is a tezos sandbox that allows you to run a minimal local tezos chain with a single command. It is designed to be a simple and easy to use tool for developers who want to quickly test their smart contracts or dapps on a local tezos chain.

### How to use TezBox?

To use TezBox, you need to have OCI compatible container runtime installed on your machine (e.g. docker, podman...). You can run TezBox with the following command:

```bash
# to run chain with the O protocol
docker run -it -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v19.1 oxfordbox
# or to run in the background
docker run -d -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v19.1 oxfordbox

# to run chain with the P protocol
docker run -it -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v20.0-rc1 parisbox
# or to run in the background
docker run -d -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v20.0-rc1 parisbox
```
You can list available protocols with the following command:
```bash
# docker run -it <image> list-protocols
docker run -it --entrypoint tezbox ghcr.io/tez-capital/tezbox:tezos-v19.1 list-protocols
```

### Configuration

All configuration files are located in the `/tezbox/configuration` directory and merged with overrides from `/tezbox/overrides` directory. You can either mount directly configuration files or user overrides which are merged with the files from the configuration directory. The merge is performed as deep merge with overwrite. Arrays are **NOT** concatenated, but replaced with the value from the overrides. Actual configuration used during the run is located in `/tezbox/context` and is a result of the merge of all configuration files created during the initialization of the container.

NOTE: *It is not possible to define bootstrap_accounts through sandbox-parameters. Use `.../configuration/bakers.hjson` instead.*

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

#### Chain Context

Chain and protocol is automatically initialized only once during the first run. The chain and all runtime data are stored in `/tezbox/data` directory. If you want to persist your sandbox state just run it with mounted volume to `/tezbox/data` directory.

e.g.
```bash
docker run -it -v $(pwd)/sandbox-data:/tezbox -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v19.1 oxfordbox
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
   - `docker build --build-arg="PROTOCOLS=Proxford,PtParisB" --build-arg="IMAGE_TAG=octez-v20.0-rc1" -t tezbox . -f  containers/tezos/Containerfile --no-cache`

### Future development

TezBox is going to follow official octez releases and tag. You can expect new release shortly after the official release of the new octez version.

We would like to introduce tezbox minimal image with only the octez node, baker, client and the minimal configuration eventually. But there is no ETA for this feature yet.