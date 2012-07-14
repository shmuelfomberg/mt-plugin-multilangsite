package MT::MlsPlugin;
use strict;
use warnings;

sub blog_config_template {
    my ($plugin, $params, $scope) = @_;
    my $app = MT->instance;
    my $blog_id = $app->param('blog_id');
    my @objs = $app->model('mls_groups')->load({blog_id => 0});
    my ($this_blog) = grep $blog_id == $_->object_id, @objs;
    my %groups = map { ( $_->groupid, $_ ) } @objs;
    my @out;
    foreach my $obj (values %groups) {
        my (undef, undef, $name) = split '\\|', $obj->url;
        my $rec = {
            group_id => $obj->groupid,
            group_name => $name,
        };
        if ($this_blog and ($this_blog->groupid == $obj->groupid)) {
            $rec->{this_blog} = 1;
        }
        push @out, $rec;
    }
    $params->{mls_all_groups} = \@out;
    $params->{mls_blog_group_set} = ($this_blog ? 1 : 0);
    return $plugin->load_tmpl("set_blog_group.tmpl");
}

sub set_blog_group {
    my ( $cb, $plugin, $data ) = @_;
    my $group_id = $data->{blog_groupid};
    return 1 if $group_id eq '-1' or $group_id eq '0';

    my ($id, $name) = $group_id =~ m/^(\d+)x(.*)$/;
    return 1 unless defined $id;

    my $app = MT->instance;
    my $blog_id = $app->param('blog_id');
    my $gclass = $app->model('mls_groups');

    if ($id > 0) {
        # try and load the blog group object
        my $blog_g = $gclass->load({ blog_id=>0, object_datasource=>'blog', object_id=>$blog_id });
        if ($blog_g) {
            if ($blog_g->groupid != $id) {
                return $plugin->error('Can only set the blog group once');
            } else {
                # the group did not change, update the internal names
                $blog_g->url(join('|', $data->{blog_internal_name}, $data->{blog_external_name}, $name));
                $blog_g->save;
                return 1;
            }
        }
    }

    my $blog_g = $gclass->new();
    $blog_g->blog_id(0);
    $blog_g->object_id($blog_id);
    $blog_g->object_datasource('blog');
    $blog_g->url(join('|', $data->{blog_internal_name}, $data->{blog_external_name}, $name));
    $blog_g->groupid($id);
    $blog_g->obj_rev(0);
    $blog_g->update_peer_id(0);
    $blog_g->update_peer_rev(0);
    $blog_g->save;

    if ($id==0) {
        # new group, need new number
        $blog_g->groupid($blog_g->id);
        $blog_g->update;
        # make groups for all the blog objects
        foreach my $type (qw{entry page}) {
            my $iter = $app->model($type)->load_iter({blog_id => $blog_id});
            while (my $obj = $iter->()) {
                my $obj_g = $gclass->new();
                $obj_g->blog_id($blog_id);
                $obj_g->object_id($obj->id);
                $obj_g->object_datasource($obj->datasource);
                $obj_g->url($obj->permalink());
                $obj_g->groupid(0);
                $obj_g->obj_rev($obj->current_revision);
                $obj_g->update_peer_id(0);
                $obj_g->update_peer_rev(0);
                $obj_g->save;
                $obj_g->groupid($obj_g->id);
                $obj_g->update;
            }
        }
    }
    else {
        # old group, let's create a todo listing
        my @blogs = $gclass->load({ blog_id=>0, object_datasource=>'blog', groupid=>$id });
        my ($peer_blog_id) = grep { $_ != $blog_id } map $_->object_id, @blogs;
        my $iter = $gclass->load_iter({ blog_id => $peer_blog_id });
        while (my $obj = $iter->()) {
            my $obj_g = $gclass->new();
            $obj_g->blog_id($blog_id);
            $obj_g->object_id(0);
            $obj_g->object_datasource($obj->datasource);
            $obj_g->url('');
            $obj_g->groupid($obj->groupid);
            $obj_g->obj_rev(0);
            $obj_g->update_peer_id(0);
            $obj_g->update_peer_rev(0);
            $obj_g->save;
        }
    }
    return 1;
}

sub listing_info_html {
    my ($prop, $obj, $app, $opts) = @_;
    my $gclass = $app->model('mls_groups');
    my $group_id = $obj->groupid;
    my $datasource = $obj->object_datasource;

    my @all_group = $gclass->load( { groupid => $group_id } );
    my @all_entries_ids = grep $_, map $_->object_id, @all_group;
    my @all_entries = $app->model($datasource)->load({ id => \@all_entries_ids });
    my @friends = grep { $_->id != $obj->object_id } @all_entries;
    my @blog_ids = map $_->blog_id, @friends;
    my %blogs = map { ( $_->object_id => $_ ) } 
        $gclass->load({ blog_id => 0, object_datasource => 'blog', object_id => \@blog_ids });
    my %group_data = map { ( $_->object_id => $_ ) } @all_group;
    my $update_peer_id = $obj->update_peer_id;
    my $update_peer;
    if ($update_peer_id) {
        ($update_peer) = grep { $_->id == $update_peer_id } @friends;
        @friends = grep { $_->id != $update_peer_id } @friends;
    }

    my $out = '';
    require MT::Util;

    my $printer = sub {
        my ($entry, $is_peer) = @_;
        my @add_classes;
        push @add_classes, "mls_outdated" 
            if $group_data{$entry->id}->is_outdated;
        push @add_classes, "mls_was_update"
            if $is_peer and 
                ($group_data{$entry->id}->obj_rev != $obj->update_peer_rev);
        my $class_set = @add_classes ? ' class="' . join(' ', @add_classes) . '"' : '';
        my $blog = $blogs{$entry->blog_id};
        my ($short) = split '\\|', $blog->url;
        $short = MT::Util::encode_html($short, 1);
        my $title = MT::Util::encode_html($entry->title, 1);
        my $url = $app->base . $app->mt_uri( 
            mode => 'view', 
            args => { 
                '_type' => $datasource,
                'blog_id' => $entry->blog_id,
                'id' => $entry->id,
            });
        my ($new_url, $new_title);
        if ($obj->object_id == 0) {
            $new_title = 'clone';
            $new_url = $app->base . $app->mt_uri( 
                mode => 'mls_newobject', 
                args => { 
                    'blog_id' => $obj->blog_id,
                    'groupid' => $obj->groupid,
                    'clone'   => $entry->id,
                });
        }
        elsif ($is_peer) {
            $new_title = 'diff';
            $new_url = $app->base . $app->mt_uri( 
                mode => 'mls_diff', 
                args => { 
                    'blog_id' => $obj->blog_id,
                    'groupid' => $obj->groupid,
                    'object'  => $entry->id,
                });
        }
        my $new_html = '';
        if ($new_title) {
            $new_html = " <a href=\"$new_url\">($new_title)</a>";
        }
        $out .= "<span $class_set><a href=\"$url\">$short($title)</a>$new_html</span>";
    };
    $printer->($update_peer, 1) if $update_peer;
    if (@friends) {
        $out .= " Others: [";
        foreach my $friend (@friends) {
            $printer->($friend, 0);
        }
        $out .= "]";
    }
    return $out;
}

sub listing_op_html {
    my ($prop, $obj, $app, $opts) = @_;
    if ($obj->object_id) {
        my $datasource = $obj->object_datasource;
        my $entry = $app->model($datasource)->load($obj->object_id);
        my $url = $app->base . $app->mt_uri( 
            mode => 'view', 
            args => { 
                '_type' => $obj->object_datasource,
                'blog_id' => $obj->blog_id,
                'id' => $obj->object_id,
            });
        my $title = $entry->title;
        return "<a href=\"$url\">Edit $title</a>";
    }
    else {
        my $url = $app->base . $app->mt_uri( 
            mode => 'mls_newobject', 
            args => { 
                'blog_id' => $obj->blog_id,
                'groupid' => $obj->groupid,
            });
        return "<a href=\"$url\">Create new</a>";
    }
}

sub mls_filter_group_objects {
    my ($cb, $app, $filter, $options, $cols) = @_;
    $options->{terms}->{is_outdated} = 1;
    return 1;
}

sub mls_newobject {
    my $app = shift;
}

sub mls_diff {
    my $app = shift;
}

1;
