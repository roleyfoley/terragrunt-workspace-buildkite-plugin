#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

# Uncomment the following line to debug stub failures
#export BUILDKITE_AGENT_STUB_DEBUG=/dev/tty

setup() {
  export BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_NAME="testing"
  export BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_MODULE_DIR="test/test"
  export BUILDKITE_PLUGINS="[{\"github.com/roleyfoley/terragrunt-workspace#v1.0.0\":{\"name\":\"${BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_NAME}\",\"module_dir\":\"${BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_MODULE_DIR}\"}},{\"github.com/buildkite-plugins/docker-buildkite-plugin#v3.7.0\":{}}]"

  export OUTPUT_PATH="$PWD/tests/.outputs/"
  mkdir -p "${OUTPUT_PATH}"
}


@test "Generates a pipeline with a deploy module" { 
  export BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DEBUG_PIPELINE_OUTPUT="${OUTPUT_PATH}/${BATS_TEST_NAME// /"_"}.yml"

  MODULE="app"

  stub buildkite-agent \
    'pipeline upload : echo Uploading pipeline'

  stub terragrunt \
    "output-module-groups --terragrunt-working-dir ${BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_MODULE_DIR} : echo '{\"Group1\": [\"$PWD/test/test/$MODULE\"]}'"

  run "$PWD/hooks/post-command"

  assert_success
  assert_output --partial "Uploading pipeline"
  assert_output --partial ":rocket: Modules for deployment - $MODULE"

  unstub buildkite-agent
  unstub terragrunt 

  # Is pipeline valid yaml
  run yq '.' $BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DEBUG_PIPELINE_OUTPUT
  assert_success

  run yq '.steps[0].fields[0].options[0].value' $BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DEBUG_PIPELINE_OUTPUT
  assert_output $MODULE

  run yq '.steps[0].block' $BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DEBUG_PIPELINE_OUTPUT 
  assert_output ":terragrunt: [${BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_NAME}] Select Modules"

  run yq '.steps[1].label' $BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DEBUG_PIPELINE_OUTPUT 
  assert_output ":terragrunt: [${BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_NAME}] Plan Modules"

  run yq '.steps[2].block' $BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DEBUG_PIPELINE_OUTPUT 
  assert_output ":terragrunt: [${BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_NAME}] Apply Changes?"

  run yq '.steps[3].label' $BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DEBUG_PIPELINE_OUTPUT 
  assert_output ":terragrunt: [${BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_NAME}] Apply Modules"
}

@test "Generates a pipeline with a deploy module and refresh" { 
  MODULE="app"
  export BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DEBUG_PIPELINE_OUTPUT="${OUTPUT_PATH}/${BATS_TEST_NAME// /"_"}.yml"
  export BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DATA_MODULES_0="passwords"

  stub terragrunt \
    "output-module-groups --terragrunt-working-dir ${BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_MODULE_DIR} : echo '{\"Group1\": [\"$PWD/test/test/$MODULE\", \"$PWD/test/test/${BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DATA_MODULES_0}\"]}'"

  stub buildkite-agent \
    'pipeline upload : echo Uploading pipeline'

  run "$PWD/hooks/post-command"
  
  assert_success
  assert_line ":chart_with_upwards_trend: Data modules - $BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DATA_MODULES_0 "
  assert_line ":rocket: Modules for deployment - $MODULE "
  assert_line "Uploading pipeline"

  unstub terragrunt  
  unstub buildkite-agent

  # The refresh module should never be planned
  run yq '.' $BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DEBUG_PIPELINE_OUTPUT
  assert_success
  refute_output --partial "terragrunt plan --terragrunt-working-dir ${BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_MODULE_DIR}/${BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DATA_MODULES_0}"

  # The first command of the plan step should be a refresh
  run yq '.steps[1].commands[0]' $BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DEBUG_PIPELINE_OUTPUT
  assert_success
  assert_output "terragrunt refresh --terragrunt-working-dir ${BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_MODULE_DIR}/${BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DATA_MODULES_0}"  
}

@test "Generates a pipeline with a deploy module and a filter" { 
  MODULE="app"
  DANGER_MODULE="danger_module"

  export BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DEBUG_PIPELINE_OUTPUT="${OUTPUT_PATH}/${BATS_TEST_NAME// /"_"}.yml"
  export BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_ALLOWED_MODULES_0="${MODULE}"

  stub buildkite-agent \
    'pipeline upload : echo Uploading pipeline'

  stub terragrunt \
    "output-module-groups --terragrunt-working-dir ${BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_MODULE_DIR} : echo '{\"Group1\":[\"$PWD/test/test/$MODULE\",\"$PWD/test/test/$DANGER_MODULE\"]}'"

  run "$PWD/hooks/post-command"

  assert_success
  assert_line "Uploading pipeline"
  assert_line ":building_construction: Discovered modules - $MODULE $DANGER_MODULE "
  assert_line ":policeman: Modules after filtering - $MODULE "

  unstub buildkite-agent
  unstub terragrunt 

  # Is pipeline valid yaml
  run yq '.' $BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DEBUG_PIPELINE_OUTPUT
  assert_success

  run yq '.steps[0].fields[0].options[0].value' $BUILDKITE_PLUGIN_TERRAGRUNT_WORKSPACE_DEBUG_PIPELINE_OUTPUT
  assert_output $MODULE
}
