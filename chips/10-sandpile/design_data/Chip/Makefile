WORK_DIR=$(shell pwd)
TOP=top
TAG=top-run-2x2

PDK_ROOT ?= $(WORK_DIR)/../../pdk
PDK = ihp-sg13g2

.PHONY: librelane
librelane:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --run-tag $(TAG) --overwrite config.yaml
	
.PHONY: librelane-skip-synth
librelane-skip-synth:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --run-tag $(TAG) --with-initial-state runs/top-run/06-yosys-synthesis/state_out.json --from Checker.YosysUnmappedCells --overwrite config.yaml

.PHONY: view-results
view-results:
	PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) librelane --manual-pdk --last-run --flow OpenInOpenROAD config.yaml