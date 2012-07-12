package MT::MlsUpdates;
use strict;

use base qw( MT::Object );

__PACKAGE__->install_properties ({
    column_defs => {
        'id'                 => 'integer not null auto_increment',
        'blog_id'            => 'integer not null',
        'original_object_id' => 'integer not null',
        'from_obj_rev'       => 'integer not null',
        'to_obj_rev'         => 'integer not null',
        'object_id'          => 'integer not null',
        'object_datasource'  => 'string(50) not null',
        'groupid'            => 'integer not null',
    },
    indexes => {
        blog_id => 1,
        groupid => 1,
        ds_obj => { columns => [qw{ object_datasource object_id }] }, 
    },
    datasource  => 'mls_updates',
    primary_key => 'id',
    class_type  => 'mls_updates',
});



1;
