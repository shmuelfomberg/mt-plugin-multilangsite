package MT::MlsPlugin;
use strict;
use warnings;

sub prepare_blog_groups_list {
	my ($app, $params) = @_;
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
	return 1;
}



1;
