use Web::Magic -quotelike => 'web';

 web <http://www.perlmonks.org/>
   -> assert_success
   -> assert_content_type('text/html')
   -> make_absolute_urls
   -> tap(sub {
           $_ -> findnodes('~links')
              -> foreach(sub {
                      printf "%s <%s>\n",
                      $_->{title} || $_->textContent,
                      $_->{href},
                 })
      })
   -> tap(sub {
           $_ -> findnodes('~images')
              -> foreach(sub {
                      printf "IMG: <%s>\n",
                      $_->{src},
                 })
      })
   ;
