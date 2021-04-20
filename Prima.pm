package Mojo::Reactor::Prima;

use strict;
use warnings;
use Carp 'croak';
use Prima;
use Mojo::Base 'Mojo::Reactor';
use Mojo::Util qw(md5_sum steady_time);
our $VERSION = '1.00';

$ENV{MOJO_REACTOR} ||= 'Mojo::Reactor::Prima';

# XXX 
use Prima::Application;

# We have to fall back to Mojo::Reactor::Poll, since application is unique
sub new
{ 
	my $self = shift->SUPER::new;
	unless ($main::application) {
		$main::application = Prima::Application->new;
		$self->{indirect_loop} = 1;
	}
	return $self;
}

sub DESTROY
{
	my $self = shift;
	if ($self->{indirect_loop}) {
		$::applicaton->destroy;
		$::applicaton = undef;
	}
}

sub again
{
	croak 'Timer not active' unless my $timer = shift->{timers}{shift()};
	$timer->{watcher}->start;
}

sub io
{
	my ($self, $handle, $cb) = @_;
	$self->{io}{fileno($handle) // croak 'Handle is closed'} = {cb => $cb};
	return $self->watch($handle, 1, 1);
}

sub is_running { !!shift->{running} }

sub next_tick
{
	my ($self, $cb) = @_;
	push @{$self->{next_tick}}, $cb;
	$self->{next_timer} //= $self->timer(0 => \&_next);
	return undef;
}

sub one_tick
{
	my $self = shift;
	local $self->{running} = 1 unless $self->{running};
	$::applicaton->yield;
}

sub recurring { shift->_timer(1, @_) }

sub remove
{
	my ($self, $remove) = @_;
	my $obj;
	return 0 unless defined $remove;
	if ( ref($remove)) {
		$obj = delete $self->{io}{fileno($remove) // croak 'Handle is closed'};
	} else {
		$obj = delete $self->{timers}{$remove};
	}
	$obj->{watcher}->destroy if $obj && $obj->{watcher};
	return !!$obj;
}

sub reset
{
	my $self = shift;
	$_->destroy for 
		grep { defined }
		map { $_->{watcher} }
		values(%{ $self->{io} }), values %{ $self->{timers} };
	delete @{$self}{qw(events io next_tick next_timer timers)}
}

sub start
{
	my $self = shift;
	local $self->{running} = ($self->{running} || 0) + 1;
	$::application->go;
}

sub stop
{
	delete shift->{running}; 
	$::application->stop;
}

sub timer { shift->_timer(0, @_) }

sub _watch_read_cb
{
	my ($self, $obj, $fd) = @_;
	$self->_try('I/O watcher', $self->{io}{$fd}{cb}, 0);
}

sub _watch_write_cb
{
	my ($self, $obj, $fd) = @_;
	$self->_try('I/O watcher', $self->{io}{$fd}{cb}, 1);
}

sub watch
{
	my ($self, $handle, $read, $write) = @_;

	my $fd = fileno $handle;
	croak 'I/O watcher not active' unless my $io = $self->{io}{$fd};

	my $mode = 0;
	$mode |= fe::Read  if $read;
	$mode |= fe::Write if $write;

	if ($mode == 0) {
		my $obj = delete $io->{watcher};
		$obj->destroy if $obj;
	}
	elsif (my $obj = $io->{watcher}) {
		$obj->mask($mode);
	} else {
		$io->{watcher} = Prima::File->new(
			fd      => $fd,
			mask    => $mode,
			onRead  => sub { $self->_try('I/O watcher', $self->{io}{$fd}{cb}, 0) },
			onWrite => sub { $self->_try('I/O watcher', $self->{io}{$fd}{cb}, 1) },
		);
	}

	return $self;
}

sub _id
{
	my $self = shift;
	my $id;
	do { $id = md5_sum 't' . steady_time . rand } while $self->{timers}{$id};
	return $id;
}

sub _timer
{
	my ($self, $recurring, $after, $cb) = @_;
	$after ||= 0.0001 if $recurring;
	my $id  = $self->_id;
	$self->{timers}{$id}{watcher} = Prima::Timer->new(
		timeout => $after,
		onTick  => sub {
			unless ($recurring) {
				$_[0]->stop;
	  			delete $self->{timers}{$id};
			}
	  		$self->_try('Timer', $cb);
		},
	);
	return $id;
}

sub _try
{
	my ($self, $what, $cb) = @_;
	eval { $self->$cb(@_); 1 } or $self->emit(error => "$what failed: $@");
}

1;

