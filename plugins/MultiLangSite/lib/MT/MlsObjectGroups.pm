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
        'is_primary'        => 'boolean not null',
    },
    indexes => {
        groupid => 1,
        blog_id => 1,
        ds_obj => { columns => [qw{ object_datasource object_id }] }, 
    },
    defaults => {
        is_primary => 0,
    },
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

1;
