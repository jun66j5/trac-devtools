# -*- coding: utf-8 -*-

import sys
sockaddr = sys.argv[1]

try:
     from trac.web.main import dispatch_request
     import trac.web._fcgi

     fcgiserv = trac.web._fcgi.WSGIServer(dispatch_request,
                                          bindAddress=sockaddr,
                                          umask=0o007)
     fcgiserv.run()

except SystemExit:
    raise
except Exception as e:
    write = sys.stdout.write
    write('Content-Type: text/plain\r\n'
          '\r\n'
          'Oops...\n'
          '\n'
          'Trac detected an internal error:\n'
          '\n')
    write(str(e))
    print('\n\n')
    import io, traceback
    out = io.StringIO()
    traceback.print_exc(file=out)
    print(out.getvalue())
