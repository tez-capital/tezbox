return {
	activatorAccount = {
		pk = "edpkuSLWfVU1Vq7Jg9FucPyKmma6otcMHac9zG4oU1KMHSTBpJuGQ2",
		sk = "unencrypted:edsk31vznjHSSpGExDMHYASz45VZqXN4DPxvsa4hAyY8dHM28cZzp6"
	},
	protocolFileId = "protocol.json",
	sandboxParametersFileId = "sandbox-parameters.json",
	voteFileId = "vote-file.json",
	MUTEZ_MULTIPLIER = 1000000,
	dal = {
		scripts = {
			setup = "https://gitlab.com/tezos/tezos/-/raw/master/scripts/install_dal_trusted_setup.sh",
			dependencies = {
				"https://gitlab.com/tezos/tezos/-/raw/master/scripts/version.sh"
			}
		},
		services = {
			"dal",
			"baker"
		}
	}
}
