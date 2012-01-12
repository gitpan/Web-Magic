#!/usr/bin/perl

use 5.010;
use Web::Magic 0.005 -quotelike => 'web';

# Newest questions on PerlMonks.org

printf(
	"%s\n<%s>\n\n",
	$_->textContent,
	URI->new_abs($_->getAttribute('href'), 'http://www.perlmonks.org/'),
	)
	foreach web <http://www.perlmonks.org/?node=Newest%20Nodes>
		-> assert_success
		-> querySelector('h3 a[name="toc-Questions"]')
		-> parentNode
		-> nextSibling
		-> querySelectorAll('tr td a[title]');

