use Data::Dumper;
use Web::Magic -sub => 'W';

my $vid = W(GET => 'http://www.youtube.com/watch', v => '7aeIpW0Tkvc');
print Dumper( $vid->opengraph );