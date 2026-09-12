# @timeout moves the child into its own process group, so the terminal's
# group-wide Ctrl-C never reaches it. Before jake forwarded signals itself,
# killing jake here left the sleep running, reparented to init.

@timeout 10m
task sleeper:
    sleep 31337
