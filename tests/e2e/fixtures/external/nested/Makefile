.PHONY: nested-list args

nested-list:
	@echo "NESTED_EXTERNAL_OK"

args:
	@printf 'ARGS=%s\n' "$(filter-out $@,$(MAKECMDGOALS))"
	@[ "$$(basename "$$(pwd)")" = "nested" ] && echo "CWD_OK"

%:
	@:
