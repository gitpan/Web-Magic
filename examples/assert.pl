use Web::Magic;

Web::Magic::Exception -> Trace( 1 );

my $a = Web::Magic
	->new(GET => 'http://www.google.co.uk/')
	->assert_response(success => sub {$_->is_success})
	->do_request;

my $b = Web::Magic
	->new(GET => 'http://www.google.co.uk/adgawertgwretgwrtgw')
	->assert_response(success => sub {$_->is_success})
	->do_request;

