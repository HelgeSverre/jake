#!/usr/bin/env python3

import os
import random
import time


def main() -> int:
    seed = int(time.time_ns()) ^ os.getpid()
    random.seed(seed)
    print(random.randint(20000, 60000))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
