package Bio::P3::Workspace::WorkspaceClientExt;

use Data::Dumper;
use strict;
use base 'Bio::P3::Workspace::WorkspaceClient';
use LWP::UserAgent;
use File::Slurp;

sub copy_files_to_handles
{
    my($self, $use_shock, $token, $file_handle_pairs) = @_;

    my $ua;
    if ($use_shock)
    {
	$ua = LWP::UserAgent->new();
	$token = $token->token if ref($token);
    }

    my %fhmap = map { @$_ } @$file_handle_pairs;
    my $res = $self->get({ objects => [ map { $_->[0] } @$file_handle_pairs] });

    # print Dumper(\%fhmap, $file_handle_pairs, $res);
    for my $i (0 .. $#$res)
    {
	my $ent = $res->[$i];
	my($meta, $data) = @$ent;

	if (!defined($meta->[0]))
	{
	    my $f = $file_handle_pairs->[$i]->[0];
	    die "Workspace object not found for $f\n";
	}

	bless $meta, 'Bio::P3::Workspace::ObjectMeta';
	my $fh = $fhmap{$meta->full_path};

	if ($use_shock && $meta->shock_url)
	{
	    my $cb = sub {
		my($data) = @_;
		print $fh $data;
	    };

	    my $res = $ua->get($meta->shock_url. "?download",
			       Authorization => "OAuth " . $token,
			       ':content_cb' => $cb);
	    if (!$res->is_success)
	    {
		warn "Error retrieving " . $meta->shock_url . ": " . $res->content . "\n";
	    }
	}
	else
	{
	    print $fh $data;
	}
    }
}


sub save_data_to_file
{
    my($self, $data, $metadata, $path, $type, $overwrite, $use_shock, $token) = @_;

    $type ||= 'unspecified';

    if ($use_shock)
    {
	local $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;

	$token = $token->token if ref($token);
	my $ua = LWP::UserAgent->new();

	my $res = $self->create({ objects => [[$path, $type, $metadata ]],
				overwrite => ($overwrite ? 1 : 0),
				createUploadNodes => 1 });
	if (!ref($res) || @$res == 0)
	{
	    die "Create failed";
	}
	$res = $res->[0];
	my $shock_url = $res->[11];
	$shock_url or die "Workspace did not return shock url. Return object: " . Dumper($res);
	
	my $req = HTTP::Request::Common::POST($shock_url, 
					      Authorization => "OAuth " . $token,
					      Content_Type => 'multipart/form-data',
					      Content => [upload => [undef, 'file', Content => $data]]);
	$req->method('PUT');
	my $sres = $ua->request($req);
	if (!$sres->is_success)
	{
	    die "Failure writing to shock at $shock_url: " . $sres->code . " " . $sres->content;
	}
	print STDERR Dumper($sres->content);
    }
    else
    {
	my $res = $self->create({ objects => [[$path, $type, $metadata, $data ]],
				overwrite => ($overwrite ? 1 : 0) });
	print STDERR Dumper($res);
    }
}

sub save_file_to_file
{
    my($self, $local_file, $metadata, $path, $type, $overwrite, $use_shock, $token) = @_;

    $type ||= 'unspecified';

    if ($use_shock)
    {
	local $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;

	$token = $token->token if ref($token);
	my $ua = LWP::UserAgent->new();

	my $res = $self->create({ objects => [[$path, $type, $metadata ]],
				overwrite => ($overwrite ? 1 : 0),
				createUploadNodes => 1 });
	if (!ref($res) || @$res == 0)
	{
	    die "Create failed";
	}
	$res = $res->[0];
	my $shock_url = $res->[11];
	
	my $req = HTTP::Request::Common::POST($shock_url, 
					      Authorization => "OAuth " . $token,
					      Content_Type => 'multipart/form-data',
					      Content => [upload => [$local_file]]);
	$req->method('PUT');
	my $sres = $ua->request($req);
	print STDERR Dumper($sres->content);
    }
    else
    {
	my $res = $self->create({ objects => [[$path, $type, $metadata, scalar read_file($local_file) ]],
				overwrite => ($overwrite ? 1 : 0) });
	print STDERR Dumper($res);
    }
}

sub opendir
{
    my($self, $path) = @_;

    my $res = $self->ls({paths => [$path]});
    my $info = $res->{$path};
    if ($info)
    {
	#
	# Need to treat root path names differently than others
	# because it lists workspaces (/username/workspacename)
	# and not the visible usernames as one might expect.
	# Here we are modeling a file hierarchy so an opendir
	# on / should return the user names that are visible.
	#

	if ($path =~ m,^/+$,)
	{
	    #
	    # We need to manipulate the output here to force everything
	    # to folders named with the username; we also need to make
	    # that list of usernames unique.
	    #
	    # Perms are all 'r' as one cannot create a user.
	    #

	    my %users = map { my $n = $_->[2]; $n =~ s,^/,,; $n =~ s,/$,,; ($n => $_->[3]) } @$info;
	    $info = [ map { [$_, 'folder', '/', $users{$_}, undef, $_, 0, {}, {}, 'r', 'r', '' ]} sort keys %users];
	}
	return [$info, 0];
    }
}

sub readdir
{
    my($self, $handle, $details) = @_;
    if (wantarray)
    {
	my $contents = $handle->[0];
	my $idx = $handle->[1];
	return undef if $idx >= @$contents;
	$handle->[1] = $#$contents;
	return map { $details ? $_ : $_->[0] } @$contents[$idx..$#$contents];
    }
    else
    {
	my $idx = $handle->[1]++;
	return $details ? $handle->[0]->[$idx] : $handle->[0]->[$idx];
    }
}

sub stat
{
    my($self, $path) = @_;
    my $res = $self->get({ objects => [$path] });
    my $ent  = $res->[0];
    my $meta = $ent->[0];
    print Dumper($meta);
}

package Bio::P3::Workspace::ObjectMeta;
sub name { return $_[0]->[0] };
sub type { return $_[0]->[1] };
sub path { return $_[0]->[2] };
sub full_path { return join("", @{$_[0]}[2,0]); }
sub creation_time { return $_[0]->[3] };
sub id { return $_[0]->[4] };
sub owner { return $_[0]->[5] };
sub size { return $_[0]->[6] };
sub user_metadata { return $_[0]->[7] };
sub auto_metadata { return $_[0]->[8] };
sub user_permission { return $_[0]->[9] };
sub global_permission { return $_[0]->[10] };
sub shock_url { return $_[0]->[11] };
1;
