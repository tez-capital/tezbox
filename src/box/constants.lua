return {
	activator_account = {
		pk = "edpkuSLWfVU1Vq7Jg9FucPyKmma6otcMHac9zG4oU1KMHSTBpJuGQ2",
		sk = "unencrypted:edsk31vznjHSSpGExDMHYASz45VZqXN4DPxvsa4hAyY8dHM28cZzp6"
	},
	protocol_file_id = "protocol.json",
	sandbox_parameters_file_id = "sandbox-parameters.json",
	vote_file_id = "vote-file.json",
	MUTEZ_MULTIPLIER = 1000000,
	dal = {
		scripts = {
			setup = "https://gitlab.com/tezos/tezos/-/raw/master/scripts/install_dal_trusted_setup.sh",
			dependencies = {
				"https://gitlab.com/tezos/tezos/-/raw/master/scripts/version.sh"
			}
		},
		services = {
			"dal"
		}
	}
}
