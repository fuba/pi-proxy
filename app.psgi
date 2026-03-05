#!/usr/bin/perl
# Simple S3 proxy for pi.fuba.me
# Fetches objects from s3://BUCKET/S3_PREFIX/ and serves them directly.

use strict;
use warnings;

use Amazon::S3::Thin;
use MIME::Types;
use Plack::Builder;

my $bucket = $ENV{S3_BUCKET}    || die "S3_BUCKET required";
my $region = $ENV{AWS_REGION}   || 'ap-northeast-1';
my $prefix = $ENV{S3_PREFIX}    || 'www/pi';

warn "pi-proxy: bucket=$bucket prefix=$prefix region=$region\n";

my $s3 = Amazon::S3::Thin->new({
    credential_provider => 'env',
    region              => $region,
});

my $mime = MIME::Types->new;

# In-memory cache: path => { content, content_type, time }
my %cache;
my $cache_ttl = 3600; # 1 hour

builder {
    sub {
        my $env = shift;

        my $result = eval {
            my $path = $env->{PATH_INFO} || '/';

            # Default to index.html for directory-like paths
            $path .= 'index.html' if $path =~ /\/$/;

            # Strip leading slash
            $path =~ s{^/}{};

            # Serve from cache if fresh
            if (my $c = $cache{$path}) {
                if (time - $c->{time} < $cache_ttl) {
                    return [200, [
                        'Content-Type'   => $c->{content_type},
                        'Content-Length' => length($c->{content}),
                        'Cache-Control'  => 'public, max-age=86400',
                    ], [$c->{content}]];
                }
            }

            # Fetch from S3
            my $key = "$prefix/$path";
            my $res = $s3->get_object($bucket, $key);

            # Fallback: bare image files (e.g. /foo.png) -> pics/foo.png
            if (!$res->is_success && $path =~ /\.(?:jpg|png|gif)$/i && $path !~ /\//) {
                my $alt_key = "$prefix/pics/$path";
                $res = $s3->get_object($bucket, $alt_key);
            }

            unless ($res->is_success) {
                return [404, ['Content-Type' => 'text/plain'], ["Not Found: $path"]];
            }

            my $content = $res->content;
            my $mt = $mime->mimeTypeOf($path);
            my $content_type = $mt ? $mt->type : 'application/octet-stream';

            # Cache it
            $cache{$path} = {
                content      => $content,
                content_type => $content_type,
                time         => time,
            };

            return [200, [
                'Content-Type'   => $content_type,
                'Content-Length' => length($content),
                'Cache-Control'  => 'public, max-age=86400',
            ], [$content]];
        };

        if ($@) {
            warn "pi-proxy error: $@\n";
            return [500, ['Content-Type' => 'text/plain'], ["Internal Server Error"]];
        }

        return $result;
    };
};
