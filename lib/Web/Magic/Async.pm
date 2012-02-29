package Web::Magic::Async;

use 5.010;
use common::sense;
use namespace::sweep; # namespace::autoclean breaks overloading
use utf8;

BEGIN {
	$Web::Magic::Async::AUTHORITY = 'cpan:TOBYINK';
	$Web::Magic::Async::VERSION   = '0.008';
}

use AnyEvent::HTTP;
use Object::Stash qw/_async/;
use Scalar::Util qw/blessed/;

use base 'Web::Magic';

sub import { goto &Web::Magic::import }

sub do_request
{
	my ($self, %extra_headers) = @_;

	if ($self->is_cancelled)
	{
		Web::Magic::Exception::BadPhase::WillNotRequest->throw(
			message      => "Need to perform HTTP request, but it is cancelled\n",
			cancellation => $self->is_cancelled,
			);
	}
	
	unless (exists $self->_async->{anyevent_http})
	{
		my $req = $self->_final_request_object(
			User_Agent => $self->_ua_string,
			%extra_headers,
			);
		
		$self->_async(
			got_head         => AnyEvent->condvar,
			got_body         => AnyEvent->condvar,
			partial_body     => '',
			);
		$self->_async->{got_head}->begin;
		$self->_async->{got_body}->begin;
		
		$self->_async->{anyevent_http} =
			http_request $req->method, $req->uri,
				headers => { map { (lc $_, $req->header($_)) } $req->header_field_names },
				body    => $req->content,
				on_header => sub { $self->__header_callback(@_); 1 },
				on_body   => sub { $self->__body_callback(@_); 1 },
				sub { $self->__final_callback(@_); 1 };
	}
	
	$self;
}

sub user_agent
{
	my ($self) = @_;
	Web::Magic::Exception->throw('Web::Magic::Async does not use LWP::UserAgent');
}

sub _cancel_progress
{
	my ($self) = @_;
	delete $self->_async->{anyevent_http};
	delete $self->_async->{got_body};
	delete $self->_async->{got_head};
	$self;
}

sub __header_callback
{
	my ($self, $headers) = @_;
	my %h_clone = %$headers;
	
	$self->_async(
		status      => delete $h_clone{Status},
		reason      => delete $h_clone{Reason},
		httpversion => delete $h_clone{HTTPVersion},
		);
	
	$self->_async(
		headers => HTTP::Headers->new(%h_clone),
		);
	
	$self->_async->{got_head}->send;
	$self;
}

sub __body_callback
{
	my ($self, $body) = @_;

	$self->_async->{partial_body} .= $body;
	
	$self;
}

sub __final_callback
{
	my ($self, $body, $hash) = @_;
	
	$self->_stash->{response} = HTTP::Response->new(
		(delete $self->_async->{status}),
		(delete $self->_async->{reason}),
		(delete $self->_async->{headers}),
		(delete $self->_async->{partial_body}).$body
		);

	local $@ = undef;
	eval {
		$self->_check_assertions($self->_stash->{response}, @{ $self->_stash->{assert_response} // [] });
	};
	if (my $err = $@)
	{
		$self->_async->{failed_assertion} = $err;
	}
	
	$self->_async->{got_body}->send;
	$self;
}

sub response
{
	my ($self, %extra_headers) = @_;
	
	return $self->_stash->{response}
		if $self->_stash->{response};
	
	$self->do_request(%extra_headers)
		unless $self->_async->{got_body};
	
	$self->_async->{got_body}->recv
		unless $self->_stash->{response};
	
	if ($self->_async->{failed_assertion})
	{
		die delete $self->_async->{failed_assertion};
	}
	
	$self->_stash->{response};
}

sub headers
{
	my ($self) = @_;

	return $self->_stash->{response}->headers
		if $self->_stash->{response};

	$self->do_request
		unless $self->_async->{got_head};

	$self->_async->{got_head}->recv
		unless $self->_async->{headers};

	if ($self->_async->{failed_assertion})
	{
		die delete $self->_async->{failed_assertion};
	}

	$self->_async->{headers} // $self->_stash->{response}->headers;
}

sub is_requested
{
	my ($self) = @_;
	
	if ($self->is_in_progress)
	{
		$self->_async->{got_body}->recv;
	}
	
	my $stash = $self->_stash;
	if (exists $stash->{response})
	{
		return $stash->{response};
	}
	
	return;
}
	
sub is_in_progress
{
	my ($self) = @_;
	my $stash  = $self->_async;
	return (exists $stash->{got_body} && !$stash->{got_body}->ready);
}

sub cancel
{
	my ($self) = @_;
	if ($self->is_in_progress)
	{
		$self->_cancel_progress;
	}
	
	return $self->SUPER::cancel;
}

1;

__END__

=head1 NAME

Web::Magic::Async - asynchronous HTTP dwimmery

=head1 SYNOPSIS

 use Web::Magic::Async -sub => 'W'; 
 say W('http://json-schema.org/card')->{description};

=head1 DESCRIPTION

An asynchronous drop-in replacement for L<Web::Magic>. Differences are
noted below.

=over

=item C<< do_request >>

Starts the HTTP request in the background, and returns immediately.
While in Web::Magic, you'd rarely call this method explicitly, in
Web::Magic::Async, call it as soon as you can (once you've finished
specifying request headers, etc) so that your code can get on with
other stuff while the HTTP stuff happens in the background.

=item C<< response >>

Blocks until the HTTP request has completed.

=item C<< headers >>

Blocks until at least the HTTP headers have been received.

=item C<< is_requested >>

If a request is in progress, blocks until it has finished before
returning true.

=item C<< is_in_progress >>

Returns true if and only if the HTTP request is currently in progress.
This method does not exist in Web::Magic itself.

=item C<< cancel >>

Usually, this will throw an error if called on a Web::Magic object that
has already been requested. Asynchronous requests can be cancelled while
they are still in progress, but not once they are complete.

=item C<< user_agent >>

Web::Magic::Async does not use LWP::UserAgent, so this method throws a
Web::Magic::Exception.

=back

=head1 BUGS

Uncountable, almost certainly.

Have a go at counting them here:
L<http://rt.cpan.org/Dist/Display.html?Queue=Web-Magic>.

Web::Magic::Async probably has more bugs lurking within it than
Web::Magic does. Unless you absolutely need the extra asynchronous
magic it provides, it's probably better to stick with Web::Magic for
now.

=head1 SEE ALSO

L<Web::Magic>, L<AnyEvent>, L<AnyEvent::HTTP>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2011-2012 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

