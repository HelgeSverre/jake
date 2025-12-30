task a:
    echo "Task A started"
    sleep 0.1
    echo "Task A done"

task b:
    echo "Task B started"
    sleep 0.1
    echo "Task B done"

task c:
    echo "Task C started"
    sleep 0.1
    echo "Task C done"

task all: [a, b, c]
    echo "All tasks complete"
