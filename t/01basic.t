use Test::More tests => 3;
BEGIN { use_ok('Web::Magic') };

can_ok 'Web::Magic', 'random_jackbauer_fact';

ok(
	!Web::Magic->can('random_jackbauer_fiction'),
	"!Web::Magic->can('random_jackbauer_fiction')",
	);
