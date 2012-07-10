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
        my (undef, undef, $name) = split '|', $obj->url;
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

    # $mt_support_save_config_filter = 1;

    # my $app = MT->instance;

    # my $facebook_api_key    = $data->{facebook_app_key};
    # my $facebook_api_secret = $data->{facebook_app_secret};

    # return __check_api_configuration( $app, $plugin, $facebook_api_key,
    #     $facebook_api_secret );
}

1;
