use 5.010;
use lib "lib";
use Web::Magic -quotelike => 'web';

web <http://www.google.co.uk/>
	-> assert_success
	-> assert_content_type('text/html')
	-> make_absolute_urls
	-> findnodes('~links')
	-> foreach(sub {
		printf "%s <%s>\n",
			$_->getAttribute('title')||$_->textContent,
			$_->getAttribute('href'),
		})
	;
