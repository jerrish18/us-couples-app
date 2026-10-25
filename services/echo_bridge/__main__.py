import sys
if len(sys.argv) > 1 and sys.argv[1] == 'login':
    from .login import main
else:
    from .server import main
main()
