package MT::MlsObjectGroups;
use strict;

use base qw( MT::Object );

__PACKAGE__->install_properties ({
    column_defs => {
        'id'                => 'integer not null auto_increment',
        'blog_id'           => 'integer not null',
        'object_id'         => 'integer not null',
        'object_datasource' => 'string(50) not null',
        # if datasource='blog', url contains "Short name|Public name|group name"
        'url'               => 'string(255) not null',
        'groupid'           => 'integer not null',
        'obj_rev'           => 'integer not null',
        'is_outdated'       => 'boolean not null',
        'update_peer_id'    => 'integer not null',
        'update_peer_rev'   => 'integer not null',
    },
    indexes => {
        groupid => 1,
        blog_id => 1,
        ds_obj => { columns => [qw{ object_datasource object_id }] }, 
    },
    # defaults => {
    #     update_peer_id => 0,
    # },
    datasource  => 'mls_groups',
    primary_key => 'id',
    class_type  => 'mls_groups',
});

sub get_entry_info {
    my ($app, $entry) = @_;
    my $mclass = $app->model('mls_groups');
    my $o_ds = $entry->datasource;
    my $og = $mclass->load({ object_id => $entry->id, object_datasource => $o_ds });
    return $app->errtrans('Invalid Request.') unless $og;
    my $group = $og->groupid;
    my @everyone = $mclass->load({ groupid => $group });
    my @peers = grep { $_->id != $og->id } @everyone;
    my ($p_obj) = grep { $_->is_primary } @everyone;
    return {
        Groupid => $group,
        is_primary => $og->is_primary,
        who_primary => (defined $p_obj ? $p_obj->id : undef),
        everyone => [ map $_->id, @everyone ],
        peers => [ map $_->id, @peers ],
    };
}

sub new_for_entry {
    my ($class, $obj, $group_id) = @_;
    $group_id ||= 0;
    my $g_obj = $class->new();
    $g_obj->blog_id($obj->blog_id);
    $g_obj->object_id($obj->id);
    $g_obj->object_datasource($obj->datasource);
    $g_obj->url($obj->permalink());
    $g_obj->groupid(0);
    $g_obj->obj_rev($obj->current_revision);
    $g_obj->is_outdated(0);
    $g_obj->update_peer_id(0);
    $g_obj->update_peer_rev(0);
    $g_obj->save;
    if (not $group_id) {
        $g_obj->groupid($g_obj->id);
        $g_obj->update;
    }
    return $g_obj;
}

sub new_placeholder {
    my ($class, $blog_id, $datasource, $group_id) = @_;
    my $g_obj = $class->new();
    $g_obj->blog_id($blog_id);
    $g_obj->object_id(0);
    $g_obj->object_datasource($datasource);
    $g_obj->url('');
    $g_obj->groupid($group_id);
    $g_obj->obj_rev(0);
    $g_obj->is_outdated(1);
    $g_obj->update_peer_id(0);
    $g_obj->update_peer_rev(0);
    return $g_obj;
}

sub BlogHasGroup {
    my $app = MT->app;
    return $app->model('mls_groups')->exist( 
        { blog_id => 0, 
          object_id => $app->blog->id, 
          object_datasource => 'blog', 
        });
}

1;
