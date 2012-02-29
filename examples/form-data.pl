use Web::Magic;

print "=================================================\n";

Web::Magic
	-> new("http://example.com/")
	-> POST([Foo => 1, Bar => 2, Foo => 'xYzZY'])
	-> Content_Type('multipart/form-data')
	-> tap( sub { print $_->_final_request_object->as_string } )
	-> cancel;

print "=================================================\n";

my $bar = XML::LibXML
	-> load_xml(IO => \*DATA)
	-> findnodes('//bar')
	-> get_node(1);

Web::Magic
	-> new("http://example.com/")
	-> POST($bar)
	-> Content_Type('text/x-bar+xml')
	-> tap( sub { print $_->_final_request_object->as_string } )
	-> cancel;

print "=================================================\n";

__DATA__
<foo><bar /></foo>
