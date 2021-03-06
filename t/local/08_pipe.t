#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Net::SSLeay;
use Symbol qw( gensym );
use IO::Handle;
use File::Spec;
use Config;

BEGIN {
  plan skip_all => "Either pipes or fork() not supported on $^O"
      if ($^O eq 'MSWin32' || !$Config{d_fork});
}

plan tests => 11;

Net::SSLeay::randomize();
Net::SSLeay::load_error_strings();
Net::SSLeay::OpenSSL_add_ssl_algorithms();

my $cert = File::Spec->catfile(qw( t data cert.pem ));
my $key  = File::Spec->catfile(qw( t data key.pem  ));

my $how_much = 1024 ** 2;

my $rs = gensym();
my $ws = gensym();
my $rc = gensym();
my $wc = gensym();

pipe $rs, $wc or die "pipe 1 ($!)";
pipe $rc, $ws or die "pipe 2 ($!)";

for my $h ($rs, $ws, $rc, $wc) {
    my $old_select = select $h;
    $| = 1;
    select $old_select;
}

my $pid = fork();
die unless defined $pid;

if ($pid == 0) {
    my $ctx = Net::SSLeay::CTX_new();
    Net::SSLeay::CTX_set_security_level($ctx, 1) if exists &Net::SSLeay::CTX_set_security_level;
    Net::SSLeay::set_server_cert_and_key($ctx, $cert, $key);

    my $ssl = Net::SSLeay::new($ctx);

    ok( Net::SSLeay::set_rfd($ssl, fileno($rs)), 'set_rfd using fileno' );
    ok( Net::SSLeay::set_wfd($ssl, fileno($ws)), 'set_wfd using fileno' );

    ok( Net::SSLeay::accept($ssl), 'accept' );

    ok( my $got = Net::SSLeay::ssl_read_all($ssl, $how_much), 'ssl_read_all' );

    is( Net::SSLeay::ssl_write_all($ssl, \$got), length $got, 'ssl_write_all' );

    Net::SSLeay::free($ssl);
    Net::SSLeay::CTX_free($ctx);

    close $ws;
    close $rs;
    exit;
}

my @results;
{
    my $ctx = Net::SSLeay::CTX_new();
    Net::SSLeay::CTX_set_security_level($ctx, 1) if exists &Net::SSLeay::CTX_set_security_level;
    my $ssl = Net::SSLeay::new($ctx);

    my $rc_handle = IO::Handle->new_from_fd( fileno($rc), 'r' );
    my $wc_handle = IO::Handle->new_from_fd( fileno($wc), 'w' );
    push @results, [ Net::SSLeay::set_rfd($ssl, $rc_handle), 'set_rfd using an io handle' ];
    push @results, [ Net::SSLeay::set_wfd($ssl, $wc_handle), 'set_wfd using an io handle' ];

    push @results, [ Net::SSLeay::connect($ssl), 'connect' ];

    my $data = 'B' x $how_much;

    push @results, [ Net::SSLeay::ssl_write_all($ssl, \$data) == length $data, 'ssl_write_all' ];

    my $got = Net::SSLeay::ssl_read_all($ssl, $how_much);
    push @results, [ $got eq $data, 'ssl_read_all' ];

    Net::SSLeay::free($ssl);
    Net::SSLeay::CTX_free($ctx);

    close $wc;
    close $rc;
}

waitpid $pid, 0;
push @results, [ $? == 0, 'server exited with 0' ];

Test::More->builder->current_test(5);
for my $t (@results) {
    ok( $t->[0], $t->[1] );
}
