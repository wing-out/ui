from __future__ import print_function
import sys
import os
from OpenType.fontdirectory import FontDirectory

def correct_fsSelection( filename ):
	try:
		with open( filename, 'rb+' ) as f:
			buf = f.read()
			fd = FontDirectory( buf )
			os2 = fd.getTable( 'OS/2' )
			head = fd.getTable( 'head' )
			macStyle = head.macStyle
			fsSelection = os2.fsSelection
			if macStyle & 1:
				fsSelection |= (1 << 5)
			else:
				fsSelection &= ~(1 << 5)
			if macStyle & 2:
				fsSelection |= (1 << 0)
			else:
				fsSelection &= ~(1 << 0)
			if not (macStyle & 3):
				fsSelection |= (1 << 6)
			else:
				fsSelection &= ~(1 << 6)
			os2.fsSelection = fsSelection
			buf = bytearray( buf )
			os2.writeInto( buf, os2.getOffset() )
			fd.updateChecksum( buf, 'OS/2' )
			fd.updateTableOfContents( buf )
			fd.updateChecksum( buf, 'head' )
			f.seek( 0 )
			f.write( bytes(buf) )
	except Exception as e:
		print( "Error correcting fsSelection: " + str( e ) )
		sys.exit( 1 )

if __name__ == '__main__':
	if len( sys.argv ) < 2:
		print( "Usage: " + sys.argv[0] + " <fontfile>" )
		sys.exit( 1 )
	correct_fsSelection( sys.argv[1] )
