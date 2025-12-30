task triple-nest:
    @if exists(/bin)
        echo "L1: /bin exists"
        @if env(HOME)
            echo "L2: HOME set"
            @if exists(/usr)
                echo "L3: /usr exists"
            @else
                echo "L3: no /usr"
            @end
            echo "L2: after L3"
        @else
            echo "L2: no HOME"
        @end
        echo "L1: after L2"
    @else
        echo "L1: no /bin"
    @end
    echo "Done"
