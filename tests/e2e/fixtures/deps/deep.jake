task prep-a:
    echo "prep-a"

task prep-b:
    echo "prep-b"

task stage1: [prep-a, prep-b]
    echo "stage1"

task stage2: [stage1]
    echo "stage2"

task stage3: [stage2]
    echo "stage3"

task final: [stage3]
    echo "final"
