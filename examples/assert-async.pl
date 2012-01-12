use 5.010;
use AnyEvent;
use Data::Dumper;
use Web::Magic::Async;

warn "A do_request";
my $a = Web::Magic::Async
	->new(GET => 'http://localhost/')
	->assert_success
	->do_request;

warn "B do_request";
my $b = Web::Magic::Async
	->new(GET => 'http://localhost/dfgsdgdf')
	->assert_success
	->do_request;

warn sprintf("A is %d length", length $a->content);
warn sprintf("B is %d length", length $b->content);
