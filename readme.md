background20<p align="center"><img width="150" src="https://raw.githubusercontent.com/tez-capital/tezbox/main/assets/logo.svg" alt="TEZBOX logo"></p>

<h2 align="center" class="heading-element">TEZBOX - tezos sandbox by tez.capital</h2>

### What is TezBox?

TezBox is a tezos sandbox that allows you to run a minimal local tezos chain with a single command. It is designed to be a simple and easy to use tool for developers who want to quickly test their smart contracts or dapps on a local tezos chain.

### Trusted By

|         |         |
|:-------:|:-------:|
|<a href="https://taqueria.io/" target="_blank"><img width="150" src="https://user-images.githubusercontent.com/1114943/150659418-e55f1df3-ba4d-4e05-ab26-1f729858c7fb.png" /></a>|<a href="https://umamiwallet.com/" target="_blank"><img height="50" src="https://raw.githubusercontent.com/trilitech/umami-v2/558eb098130b23ca04b4f359e7973b78f8e2f8f4/apps/web/src/assets/icons/logo-light.svg" /></a>|

### How to use TezBox?

To use TezBox, you need to have OCI compatible container runtime installed on your machine (e.g. docker, podman...). You can run TezBox with the following command:

# Rio

```bash
# to run chain with the PsRiotum protocol
docker run -it -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v22.1 riobox
# or to run in the background
docker run -d -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v22.1 riobox
```

# Seoul

```bash
# to run chain with the PtSeouLou protocol
docker run -it -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v22.1 S
# or to run in the background
docker run -d -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v22.1 S
```

You can list available protocols with the following command:
```bash
# docker run -it <image> list-protocols
docker run -it --entrypoint tezbox ghcr.io/tez-capital/tezbox:tezos-v22.1 list-protocols
```

#### CI

`tezbox` is commonly used in CI pipelines. If you can estimate the expected duration of a specific test and want to prevent CI from getting stuck, you can use the `--timeout=<duration>` option to limit how long the instance runs. Supported units: `s` (seconds), `m` (minutes), `h` (hours). In case of a timeout, the container exits with an exit code of `2`.

```bash
docker run -it -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v22.1 --timeout=120s riobox
```

Note: The timeout specifies how long the sandbox runs, excluding the bootstrap duration.

#### Logs

Output from each service are stored in /ascend/logs within the container. To access the logs without entering the container, mount this directory from outside the container.

#### Dal

To run a dal within tezbox start tezbox with `--with-dal` option as follows:

```bash
# to run chain with the PsRiotum protocol
docker run -it -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v22.1 riobox --with-dal
# or to run in the background
docker run -d -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v22.1 riobox --with-dal
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
# docker run -it -v <path-to-your-file>:/tezbox/overrides/protocols/<case sensitive protocol id>/sandbox-parameters.hjson ... ghcr.io/tez-capital/tezbox:tezos-v22.1 riobox
docker run -it -v $(pwd)/sandbox-override-parameters.hjson:/tezbox/overrides/protocols/PsRiotum/sandbox-parameters.hjson ... ghcr.io/tez-capital/tezbox:tezos-v22.1 riobox
```
You can determine path based on folder structure in [configuration directory](https://github.com/tez-capital/tezbox/tree/main/configuration).

Optionally you can mount entire overrides/configuration directory to `/tezbox/overrides` or `/tezbox/configuration` to replace the whole configuration.

```bash
docker run -it -v <path-to-your-configuration-overrides>:/tezbox/overrides ... ghcr.io/tez-capital/tezbox:tezos-v22.1 riobox
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
docker run -it -v $(pwd)/baker.hjson:/tezbox/overrides/services/baker.hjson ... ghcr.io/tez-capital/tezbox:tezos-v22.1 riobox
```

#### Chain Context

Chain and protocol is automatically initialized only once during the first run. The chain and all runtime data are stored in `/tezbox/context/data` directory. If you want to persist your sandbox state just run it with mounted volume to `/tezbox/context/data` directory.

e.g.
```bash
docker run -it -v $(pwd)/sandbox-data:/tezbox -p 0.0.0.0:8732:8732 ghcr.io/tez-capital/tezbox:tezos-v22.1 riobox
```

NOTE: *To reset the state you can remove the `/tezbox/context/data/tezbox-initialized` file. After its removal all chain and client data will be removed and the chain will be reinitialized on the next run.*

#### Flextesa Compatibility

To maintain some level of compatibility with flextesa, the alice and bob accounts are the same. The RPC port is exposed on ports 8732 and 20000. And we use similar protocol aliases like riobox.

But unlike flextesa the tezbox won't expose configuration through command line arguments. Instead, you can edit configuration directly in the configuration files or use overrides.

### Building TezBox

To build TezBox follow these steps:

1. clone the repository
   - `git clone https://github.com/tez-capital/tezbox && cd tezbox`
2. edit the Dockerfile, configuration and sources if needed
3. build lua sources (you can get eli [here](https://github.com/alis-is/eli/releases))
   - `eli build/build.lua`
4. build the image
   - `docker build --build-arg="PROTOCOLS=PsRiotum" --build-arg="IMAGE_TAG=octez-v22.1" -t tezbox . -f  containers/tezos/Containerfile --no-cache`

### Future development

TezBox is going to follow official octez releases and tag. You can expect new release shortly after the official release of the new octez version.

We would like to introduce tezbox minimal image with only the octez node, baker, client and the minimal configuration eventually. But there is no ETA for this feature yet.