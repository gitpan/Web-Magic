package Web::Magic::Util;

use 5.010;
use strict;
use utf8;

use XML::LibXML 1.70;

BEGIN {
	$Web::Magic::Util::AUTHORITY = 'cpan:TOBYINK';
	$Web::Magic::Util::VERSION   = '0.008';
	
	*XML_LIBXML_IS_NEW = (XML::LibXML->VERSION > 1.90) ? sub(){1} : sub(){0};
}

sub __is_code
{
	my ($code) = @_;
	
	if (ref $code eq 'CODE')
	{
		return $code;
	}
	
	if (UNIVERSAL::can($code, 'can')        # is blessed (sort of)
	and overload::Overloaded($code)         # is overloaded
	and overload::Method($code, '&{}'))     # overloads '&{}'
	{
		return $code;
	}
	
	die "Not a subroutine reference\n";
}

sub xmlsub
{
	my ($name, $coderef) = @_;
	die "wrong number of parameters" unless @_ == 2;
	return if XML::LibXML::NodeList->can($name);
	do {
		no strict 'refs';
		*{"XML::LibXML::NodeList::$name"} = $coderef;
	};
}

unless (XML_LIBXML_IS_NEW)
{
	xmlsub map => sub
	{
		my $self = CORE::shift;
		my $sub  = __is_code(CORE::shift);
		local $_;
		my @results = CORE::map { @{[ $sub->($_) ]} } @$self;
		return unless defined wantarray;
		return wantarray ? @results : (ref $self)->new(@results);
	};

	xmlsub grep => sub
	{
		my $self = CORE::shift;
		my $sub  = __is_code(CORE::shift);
		local $_;
		my @results = CORE::grep { $sub->($_) } @$self;
		return unless defined wantarray;
		return wantarray ? @results : (ref $self)->new(@results);
	};

	xmlsub sort => sub
	{
		my $self = CORE::shift;
		my $sub  = __is_code(CORE::shift);
		my @results = CORE::sort { $sub->($a,$b) } @$self;
		return wantarray ? @results : (ref $self)->new(@results);
	};

	xmlsub foreach => sub
	{
		my $self = CORE::shift;
		my $sub  = CORE::shift;
		$self->map($sub);
		return wantarray ? @$self : $self;
	};

	xmlsub reverse => sub
	{
		my $self    = CORE::shift;
		my @results = CORE::reverse @$self;
		return wantarray ? @results : (ref $self)->new(@results);
	};

	xmlsub reduce => sub
	{
		my $self = CORE::shift;
		my $sub  = __is_code(CORE::shift);
		
		my @list = @$self;
		CORE::unshift @list, $_[0] if @_;
		
		my $a = CORE::shift(@list);
		foreach my $b (@list)
		{
			$a = $sub->($a, $b);
		}
		return $a;
	};
}

__FILE__
__END__

=head1 NAME

Web::Magic::Util - Web::Magic's dumping ground

=head1 SYNOPSIS

 use Web::Magic;
 # Web::Magic automatically includes Web::Magic::Util

=head1 DESCRIPTION

This module is a helper for Web::Magic. End users probably don't need to
worry about this module directly.

=head2 XML::LibXML::NodeList methods

XML::LibXML 1.91 and above adds some handy methods to XML::LibXML::NodeList:
C<map>, C<grep>, C<sort>, C<reverse>, C<foreach> and C<reduce>.

This module backports them to XML::LibXML 1.70+.

That said, XML::LibXML 1.91+ is recommended for other reasons. The
XML::LibXML::AttributeHash feature is useful for concise, readable code.
The examples in the Web::Magic documentation often assume that you have
at least version 1.91. (And you should probably use at least 1.93 for the
overloading "==" bug fix.)

=head1 SEE ALSO

L<Web::Magic>, L<XML::LibXML::NodeList>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2012 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

