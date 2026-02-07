from __future__ import print_function
import struct
from struct import pack, unpack, calcsize, Struct
from collections import namedtuple

from .checksum import BigEndian32BitList
from .typeutils import fixed_str, panose_str, bitfield2str, int_to_tag
from .fielddesc import FieldDesc

def registerStructFields( cls ):
	cls._fdlist = FieldDesc.buildList( cls._field_desc )
	return cls

def _setup_structs( cls ):
	if not '_layout' in cls.__dict__:
		cls._layout = {}
	if not '_size' in cls.__dict__:
		cls._size = 0
	if not '_structtype' in cls.__dict__:
		cls._structtype = []
	structname = cls._classname() + 'struct'
	structdef = FieldDesc.structdefs( cls._fdlist )
	cls._layout[cls._classname()] = Struct( structdef )
	cls._size += calcsize( structdef )
	namelist = FieldDesc.namelist( cls._fdlist )
	cls._structtype.append( namedtuple( structname, namelist ) )
	strfmt = FieldDesc.formatstring( cls._name, cls._fdlist )
	cls._strcode = compile( 'self._astr = ' + strfmt, '<string>', 'exec' )
	return cls

class BaseTable( object ):
	@classmethod
	def _classname( cls ):
		return cls.__name__.rpartition( '.' )[2]

	def __init__( self, buf, offset = 0 ):
		self._offset = offset
		vals = self._layout[self.__class__.__name__].unpack_from( buf, offset )
		structconstructor = self._structtype[0]
		self.__dict__['_struct'] = structconstructor( *vals )

	def __getattr__( self, name ):
		if name in self.__dict__:
			return self.__dict__[name]
		if not '_struct' in self.__dict__:
			raise Exception( "No _struct member: " + str( self ) )
		st = self._struct
		if hasattr(st, "_asdict"):
			d = st._asdict()
			if name in d: return d[name]
		if hasattr(st, name):
			return getattr(st, name)
		raise KeyError( "item " + name + " not found" )

	def __setattr__( self, name, value ):
		if '_struct' in self.__dict__:
			st = self._struct
			if hasattr(st, "_replace") and name in st._fields:
				self.__dict__['_struct'] = st._replace(**{name: value})
				return
		self.__dict__[name] = value

	def __getitem__( self, key ):
		return self._struct[key]

	def __setitem__( self, key, value ):
		self._struct[key] = value

	def __str__( self ):
		self._astr = ''
		if hasattr( type(self), '_strcode' ):
			exec( type(self)._strcode )
		elif hasattr( self, '_strcode' ):
			exec( self._strcode )
		else:
			self._astr = repr( self )
		return self._astr

	def getOffset( self ):
		return self._offset

	def getSize( self ):
		thestruct = self._layout[self.__class__.__name__]
		return thestruct.size

	def writeInto( self, buf, offset=0 ):
		thestruct = self._layout[self.__class__.__name__]
		vals = [ self.__getattr__( i.name  ) for i in self._fdlist ]
		res = thestruct.pack_into( buf, offset, *vals )
		return res

	def getChecksum( self ):
		wL = BigEndian32BitList()
		for desc in self._field_desc:
			key = desc[0]
			val = self.__getattr__( key )
			size = FieldDesc.size_OT_type( desc[1] )
			wL.accumVal( val, size )
		return wL.get32BitSum()

class Table( BaseTable ):
	def __init__( self, buf, offset = 0 ):
		BaseTable.__init__( self, buf, offset )
	@classmethod
	def getTableSize( cls ):
		return cls._size
	@classmethod
	def getFieldDesc( cls ):
		return cls._fdlist

class VariableSizedTable( BaseTable ):
	def __init__( self, buf, offset = 0 ):
		_setup_structs( self )
		BaseTable.__init__( self, buf, offset )
	def getTableSize( self ):
		return self._size
	def getFieldDesc( self ):
		return self._fdlist

class ReferredTable( Table ):
	@classmethod
	def getTableName( cls ):
		return _tag;

class TableRecord( Table ):
	def __init__( self, buf, parent, index ):
		self._itemno = index + 1
		self._parent = parent
		offset = parent.getOffset() + parent.getTableSize() + index * type(self)._size
		Table.__init__( self, buf, offset )
	def getItemNo( self ):
		return self._itemno
	def getParentTable( self ):
		return self._parent

class StructArrayTable( VariableSizedTable ):
	def __init__( self, filebuf, offset ):
		VariableSizedTable.__init__( self, filebuf, offset )
		self._items = []
		if not getattr( self, '_item_type' ):
			raise Exception( "Subclasses must set _item_type class member" )
	def getItemSize( self ):
		return self._item_type.getTableSize()
	def getNumItems( self ):
		raise Exception( "Subclasses must override" )
	def getItems( self, filebuf ):
		if not self._items:
			size = self.getTableSize()
			self._readItems( filebuf, size + self._offset )
		return self._items
	def getItem( self, filebuf, idx ):
		self.getItems( filebuf )
		if self._items:
			return self._items[idx]
		else:
			raise Exception( 'Got no items.' )
	def _readItems( self, filebuf, start ):
		item_size = self.getItemSize()
		for i in range( self.getNumItems() ):
			sr = self._item_type( filebuf, start + item_size * i )
			self._items.append( sr )
	def getTableHeaderSize( cls ):
		return cls.getTableSize()

class NestedStructTable( BaseTable ):
	def __init__( self, buf, offset = 0 ):
		raise Exception( "Not implemented" )

class SimpleArrayTable( VariableSizedTable ):
	def __init__( self, filebuf, offset ):
		VariableSizedTable.__init__( self, filebuf, offset )
		self._items = ()
		if not hasattr( self, '_item_type' ):
			raise Exception( 'Subclasses must set _item_type class member' )
		if not FieldDesc.has_type_symbol( self._item_type ):
			raise Exception( '_item_type not a known simple type' )
	def getItems( self, filebuf ):
		if not self._items:
			size = self.getTableSize()
			self._readItems( filebuf, size + self._offset )
		return self._items
	def _readItems( self, filebuf, start ):
		item_size = FieldDesc.size_OT_type( self._item_type )
		item_format = FieldDesc.type_to_format( self._item_type )
		fmt_str = '>' + str( self.getNumItems() ) + item_format
		self._items = struct.unpack_from( fmt_str, filebuf, start )
	def getItem( self, filebuf, idx ):
		self.getItems( filebuf )
		return self._items[ idx ]
	def getTableHeaderSize( cls ):
		return cls.getTableSize()

class TableOffsetArrayTable( SimpleArrayTable ):
	_item_type = 'uint16'
	def __init__( self, filebuf, offset ):
		SimpleArrayTable.__init__( self, filebuf, offset )
		if not getattr( self, '_reference_type' ):
			raise Exception( "Subclasses must set _reference_type class member" )
	def getReferencedItems( self, filebuf ):
		return [ self.getReferencedItem( filebuf, i )
				for i in range( self.getNumItems() ) ]	
	def getReferencedItem( self, filebuf, idx ):
		off = self.getItem( filebuf, idx )
		return self._reference_type( filebuf, self._offset + off )
