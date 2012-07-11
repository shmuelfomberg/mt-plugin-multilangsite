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
    $blog_g->is_primary(0);
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
                $obj_g->url(join('|', $data->{blog_internal_name}, $data->{blog_external_name}, $name));
                $obj_g->groupid(0);
                $obj_g->obj_rev($obj->current_revision);
                $obj_g->is_primary(0);
                $obj_g->save;
                $obj_g->groupid($obj_g->id);
                $obj_g->update;
            }
        }
    }
    else {
        # old group, let's create a todo listing
        my @blogs = $gclass->load({ blog_id=>0, object_datasource=>'blog', groupid=>$id });
        my @blog_ids = grep { $_ != $blog_id } map $_->object_id, @blogs;
        my %seen_groups;
        my $uclass = $app->model('mls_updates');
        my $iter = $gclass->load_iter({ blog_id=>\@blog_ids });
        while (my $obj = $iter->()) {
            next if exists $seen_groups{$obj->groupid};
            $seen_groups{$obj->groupid} = 1;
            my $todo = $uclass->new();
            $todo->blog_id($blog_id);
            $todo->original_object_id(0);
            $todo->from_obj_rev(0);
            $todo->to_obj_rev(0);
            $todo->object_id(0);
            $todo->object_datasource($obj->object_datasource);
            $todo->groupid($obj->groupid);
            $todo->save;
        }
    }
    return 1;
}

1;
