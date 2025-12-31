# Tests for environment-dependent function edge cases

task test-home:
    echo "home: {{home()}}"

task test-shell-config:
    echo "shell_config: {{shell_config()}}"
