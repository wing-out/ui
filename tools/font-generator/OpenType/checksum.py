from __future__ import print_function
import struct
from ctypes import c_uint64, c_uint32, c_uint16, c_uint8, c_ubyte

class BigEndian32BitList( object ):
	def __init__( self ):
		self._byte_count = 0
		self._wordList = []

	def accumVal( self, val, size ):
		if size == 1:
			v = 0xFF & c_ubyte( val ).value
			self.accumByte( v )
		elif size == 2:
			v = c_uint16( val ).value
			for b in range( 0, size ):
				shift = 8 * ( size - b - 1 )
				self.accumByte( 0xFF & ( v >> shift ) )
		elif size == 4:
			v = c_uint32( val ).value
			for b in range( 0, size ):
				shift = 8 * ( size - b - 1 )
				self.accumByte( 0xFF & ( v >> shift ) )
		elif size == 8:
			v = c_uint64( val ).value
			for b in range( 0, size ):
				shift = 8 * ( size - b - 1 )
				self.accumByte( 0xFF & ( v >> shift ) )
		elif size == 10:
			for i in range( 0, size ):
				v = val[i] if isinstance(val[i], int) else ord(val[i])
				self.accumByte( 0xFF & v )
		else:
			raise Exception( "Unexpected size {}".format( size ) )

	def accumByte( self, val ):
		if self._byte_count % 4 == 0:
			self._wordList.append( 0 )
		byte_off = ( 3 - self._byte_count ) % 4
		new_byte = int( val ) << ( byte_off * 8 )
		self._wordList[-1] |= new_byte
		self._byte_count += 1

	def get32BitSum( self ):
		checksum = 0
		for w in self._wordList:
			checksum = 0xFFFFFFFF & ( checksum + w )
		return checksum

def get_file32Bit_checkSumAdjustment( f ):
	import numpy
	a = numpy.fromfile( f, dtype='>u4', count=-1 )
	s = numpy.uint64( 0 )
	for v in a:
		s += v
	cs = 0xFFFFFFFF & int( s )
	checkSumAdjustment = 0xB1B0AFBA - cs
	return 0xFFFFFFFF & checkSumAdjustment
