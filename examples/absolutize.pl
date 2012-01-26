use 5.010;
use lib "lib";
use Web::Magic -sub => 'W';

my $link_summary = sub {
	my ($node) = @_;
	return 'not a link' unless $node->nodeName eq 'a';
	sprintf '%s <%s>', $_->textContent, $_->getAttribute('href');
};

say $_->$link_summary
	foreach W(q<http://www.perlmonks.org/?node=Newest%20Nodes>)
		-> assert_success
		-> make_absolute_urls
		-> querySelector('h3 a[name="toc-Questions"]')
		-> parentNode
		-> nextSibling
		-> querySelectorAll('tr td a[title]');
