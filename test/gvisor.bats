#!/usr/bin/env bats
# vim: set syntax=sh:

# Integration tests for the CRI-O + gVisor (runsc) integration.
#
# STATUS: STUB — these tests require a patched containerd-shim-runsc-v1 that
# accepts CRI-O's Options proto (no TypeUrl) and recognises the CRI-O sandbox
# annotation for shim grouping. That fix is tracked in the companion gVisor PR.
# Until that PR merges and a patched shim binary is available in CI, all tests
# in this file skip automatically.
#
# Covers: https://github.com/cri-o/cri-o/issues/10313
# Companion gVisor PR: https://github.com/google/gvisor/pull/XXXX

load helpers

function setup() {
	setup_test
}

function teardown() {
	cleanup_test
}

function require_gvisor() {
	# Skip unless explicitly running with the gVisor VM runtime type.
	if [[ "${RUNTIME_TYPE:-}" != "vm" ]]; then
		skip "gVisor integration tests require RUNTIME_TYPE=vm"
	fi
	# Skip until a patched shim is present (companion gVisor PR not yet merged).
	if ! command -v containerd-shim-runsc-v1 &> /dev/null &&
		! [[ "${RUNTIME_BINARY_PATH:-}" == *runsc* ]]; then
		skip "containerd-shim-runsc-v1 not found — stub pending companion gVisor PR"
	fi
}

function make_init_config() {
	local out="$1" name="$2" msg="$3"
	jq --arg name "$name" --arg msg "$msg" \
		'.metadata.name = $name | .command = ["/bin/echo", $msg]' \
		"$TESTDATA"/container_config.json > "$out"
}

@test "gVisor [stub]: shim process starts on RunPodSandbox and exits on pod removal" {
	require_gvisor
	start_crio

	output="$(ps --no-headers -C containerd-shim-runsc-v1 2> /dev/null | wc -l)"
	[[ "$output" == "0" ]]

	pod_id=$(crictl runp "$TESTDATA"/sandbox_config.json)
	[ "$(ps --no-headers -C containerd-shim-runsc-v1 2> /dev/null | wc -l)" -ge "1" ]

	crictl stopp "$pod_id"
	crictl rmp "$pod_id"
	[ "$(ps --no-headers -C containerd-shim-runsc-v1 2> /dev/null | wc -l)" == "0" ]
}

@test "gVisor [stub]: init container runs and exits before app container starts (issue #10313)" {
	require_gvisor
	start_crio

	pod_id=$(crictl runp "$TESTDATA"/sandbox_config.json)

	make_init_config "$TESTDIR"/init_ctr.json "init-ctr" "init-done"
	init_id=$(crictl create "$pod_id" "$TESTDIR"/init_ctr.json "$TESTDATA"/sandbox_config.json)
	crictl start "$init_id"
	wait_until_exit "$init_id"

	app_id=$(crictl create "$pod_id" "$TESTDATA"/container_sleep.json "$TESTDATA"/sandbox_config.json)
	crictl start "$app_id"

	output=$(crictl inspect "$app_id" | jq -r '.status.state')
	[ "$output" = "CONTAINER_RUNNING" ]
}

@test "gVisor [stub]: multiple init containers run in sequence before app container" {
	require_gvisor
	start_crio

	pod_id=$(crictl runp "$TESTDATA"/sandbox_config.json)

	for i in 1 2 3; do
		make_init_config "$TESTDIR"/init_ctr_${i}.json "init-ctr-${i}" "init-step-${i}"
		ctr_id=$(crictl create "$pod_id" "$TESTDIR"/init_ctr_${i}.json "$TESTDATA"/sandbox_config.json)
		crictl start "$ctr_id"
		wait_until_exit "$ctr_id"
	done

	app_id=$(crictl create "$pod_id" "$TESTDATA"/container_sleep.json "$TESTDATA"/sandbox_config.json)
	crictl start "$app_id"

	output=$(crictl inspect "$app_id" | jq -r '.status.state')
	[ "$output" = "CONTAINER_RUNNING" ]
}

@test "gVisor [stub]: ExecSync into app container succeeds after init container exits" {
	require_gvisor
	start_crio

	pod_id=$(crictl runp "$TESTDATA"/sandbox_config.json)

	make_init_config "$TESTDIR"/init_ctr.json "init-ctr" "init-done"
	init_id=$(crictl create "$pod_id" "$TESTDIR"/init_ctr.json "$TESTDATA"/sandbox_config.json)
	crictl start "$init_id"
	wait_until_exit "$init_id"

	app_id=$(crictl create "$pod_id" "$TESTDATA"/container_sleep.json "$TESTDATA"/sandbox_config.json)
	crictl start "$app_id"

	output=$(crictl exec --sync "$app_id" /bin/echo "hello-from-exec")
	[[ "$output" == *"hello-from-exec"* ]]
}

@test "gVisor [stub]: pod sandbox reaches SANDBOX_READY state" {
	require_gvisor
	start_crio

	pod_id=$(crictl runp "$TESTDATA"/sandbox_config.json)

	output=$(crictl inspectp "$pod_id" | jq -r '.status.state')
	[ "$output" = "SANDBOX_READY" ]

	crictl stopp "$pod_id"
	crictl rmp "$pod_id"
}
