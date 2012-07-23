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
    $blog_g->is_outdated(0);
    $blog_g->update_peer_id(0);
    $blog_g->update_peer_rev(0);
    $blog_g->save or die $blog_g->errstr;

    if ($id==0) {
        # new group, need new number
        $blog_g->groupid($blog_g->id);
        $blog_g->update;
        # make groups for all the blog objects
        foreach my $type (qw{entry page}) {
            my $iter = $app->model($type)->load_iter({blog_id => $blog_id});
            while (my $obj = $iter->()) {
                my $g_obj = $gclass->new_for_entry($obj);
                $group_id = $g_obj->groupid;
            }
        }
    }
    else {
        # old group, let's create a todo listing
        my @blogs = $gclass->load({ blog_id=>0, object_datasource=>'blog', groupid=>$id });
        my ($peer_blog_id) = grep { $_ != $blog_id } map $_->object_id, @blogs;
        my $iter = $gclass->load_iter({ blog_id => $peer_blog_id });
        while (my $obj = $iter->()) {
            my $s_obj = $gclass->new_placeholder($blog_id, $obj->datasource, $obj->groupid);
            $s_obj->save();
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
    my %group_data = map { ( $_->object_id => $_ ) } grep $_->object_id, @all_group;
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
                mode => 'view', 
                args => { 
                    '_type'     => $datasource,
                    'blog_id'   => $obj->blog_id,
                    'mls_group' => $obj->groupid,
                    'mls_clone' => $entry->id,
                });
        }
        elsif ($is_peer) {
            $new_title = 'diff';
            $new_url = $app->base . $app->mt_uri( 
                mode => 'mls_diff', 
                args => { 
                    'blog_id'  => $obj->blog_id,
                    'groupid'  => $obj->groupid,
                    'object'   => $entry->id,
                    'rev_from' => $obj->update_peer_rev,
                    'rev_to'   => $group_data{$entry->id}->obj_rev,
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
            mode => 'view', 
            args => { 
                'blog_id' => $obj->blog_id,
                'mls_group' => $obj->groupid,
                '_type'   => $obj->object_datasource,
            });
        return "<a href=\"$url\">Create new</a>";
    }
}

sub mls_filter_group_objects {
    my ($cb, $app, $filter, $options, $cols) = @_;
    $options->{terms}->{is_outdated} = 1;
    return 1;
}

sub cms_edit_entry {
    my ($cb, $app, $id, $obj, $param) = @_;
    my $gclass = $app->model('mls_groups');
    my $blog_id = $app->blog->id;
    my $datasource;
    my ($group_obj, @all_group);
    if ($param->{new_object}) {
        my $group_id = $app->param('mls_group');
        return 1 unless $group_id;
        @all_group = $gclass->load( { groupid => $group_id } );
        ($group_obj) = grep { $_->blog_id == $blog_id } @all_group;
        return 1 unless $group_obj->object_id == 0;
        $datasource = $group_obj->object_datasource;
        my $tclass = $app->model($datasource);
        my $clone_id = $app->param('mls_clone');
        my $friend;

        if ($clone_id) {
            ($friend) = grep { $_->object_id == $clone_id } @all_group;
        }
        else {
            ($friend) = grep { $_->object_id != 0 } @all_group;            
        }
        return 1 unless $friend;
        my $f_obj = $tclass->load($friend->object_id);
        return 1 unless $f_obj;

        if ($clone_id) {
            my $cols = $tclass->column_names;
            for my $col (@$cols) {
                next if defined $app->param($col);
                $param->{$col} =  $f_obj->$col();
            }
        } 
        else {
            $param->{basename} = $f_obj->basename;
        }
    }
    else {
        $datasource = $obj->datasource;
        $group_obj = $gclass->load({ 
            blog_id => $blog_id, 
            object_id => $obj->id, 
            object_datasource => $datasource 
        });
        return 1 unless $group_obj;
        @all_group = $gclass->load( { groupid => $group_obj->groupid } );
    }
    $param->{mls_group} = $group_obj->groupid;
    $param->{mls_is_outdated} = $group_obj->is_outdated;
    my @peer_blog_ids = grep $_ != $blog_id, map $_->blog_id, @all_group;
    my %group_blogs = 
        map { ( $_->object_id => $_ ) } 
        $gclass->load({ 
            blog_id => 0, 
            object_id => \@peer_blog_ids,
            object_datasource => 'blog',
        });

    my @peer_recs;
    foreach my $peer (@all_group) {
        next unless $peer->object_id;
        next if $peer->object_id == $group_obj->object_id;
        my ($short) = split '\\|', $group_blogs{$peer->blog_id}->url;
        my $rec = {
            id => $peer->object_id,
            blog_id => $peer->blog_id,
            blog_short => $short,
        };
        if ($group_obj->update_peer_id == $peer->object_id) {
            $rec->{updated_from_this} = 1;
            $param->{mls_updated_from} = $rec;
            my $from = $group_obj->update_peer_rev;
            my $to = $peer->obj_rev;
            if ($from != $to) {
                $rec->{rev_from} = $from;
                $rec->{rev_to} = $to;
            }
        }
        push @peer_recs, $rec;
    }
    $param->{mls_peer_recs} = \@peer_recs;
    return 1;
}

sub cms_edit_entry_template {
    my ($cb, $app, $param, $tmpl) = @_;
    my $group_id = $param->{mls_group};
    return 1 unless $group_id;
    my $widget = $tmpl->createElement('app:widget', {
        id => 'mls_staus_widget',
        label => 'Group Status',
    });
    my $entry_status = $param->{mls_is_outdated} ? 'outdated' : 'up to date';
    my $last_updated = '';
    if (my $rec = $param->{mls_updated_from}) {
        $last_updated = '<br/>Last updated from ' . $rec->{blog_short};
        if ($rec->{rev_to}) {
            my $url = $app->base . $app->mt_uri( 
                mode => 'mls_diff', 
                args => { 
                    'blog_id'  => $app->blog->id,
                    'groupid'  => $group_id,
                    'object'   => $rec->{id},
                    'rev_from' => $rec->{rev_from},
                    'rev_to'   => $rec->{rev_to},
                });
            $last_updated .= '<a href="'.$url.'">diff</a>'
        }
    }
    $widget->appendChild(
        $tmpl->createTextNode(
            '<input type="hidden" name="mls_group" value="'.$group_id.'" />'.
            '<div class="status">'.
                'Entry is ' . $entry_status . $last_updated .
            '</div>')
    );
    my $select = $tmpl->createElement('app:setting', {
        id => 'mls_set_status',
        label => 'Set Entry Status',
        label_class => 'top-label',
        show_label => 0,
        });
    my $select_code = '<select id="mls_status_select" name="mls_status_select">';
    $select_code .= '<option value="0" selected>Set entry status...</option>';
    if (not $param->{mls_is_outdated}) {
        $select_code .= '<option value="new_version">Declare new version</option>';
    }
    my $peer_recs = $param->{mls_peer_recs};
    foreach my $rec (@$peer_recs) {
        my $val = "x" . $rec->{blog_id} . 'x' . $rec->{id};
        $select_code .= '<option value="'.$val.'">Match to '.$rec->{blog_short}.'</option>';
    }
    $select_code .= '</select>';
    $select->innerHTML($select_code);
    $widget->appendChild($select);
    $tmpl->insertAfter($widget, $tmpl->getElementById('entry-status-widget'));
    return 1;
}

sub cms_post_save_entry_handle_others {
    my ($app, $obj, $g_obj) = @_;
    my $group_id = $g_obj->groupid;
    my $gclass = $app->model('mls_groups');
    my $status_select = $app->param('mls_status_select') || '';
    my $dirty = 0;

    my @others = 
        grep { $_->object_id and ( $_->object_id != $obj->id ) } 
        $gclass->load({ object_datasource => $obj->datasource, groupid => $group_id });
    if (not @others) {
        # no others - this objects is always updated and in the last version
        $g_obj->obj_rev($obj->current_revision);
        $dirty = 1;
    }
    elsif ($status_select eq 'new_version') {
        $g_obj->is_outdated(0);
        $g_obj->obj_rev($obj->current_revision);
        foreach my $o (@others) {
            $o->is_outdated(1);
            $o->save;
        }
    }
    elsif ($status_select =~ m/^x(\d+)x(\d+)$/) {
        my $o_blog_id = $1;
        my $o_obj_id = $2;
        my ($o_obj_g) = grep { $_->object_id == $o_obj_id } @others;
        return 1 unless $o_obj_g;
        $g_obj->obj_rev($obj->current_revision);
        $g_obj->update_peer_id($o_obj_id);
        $g_obj->update_peer_rev($o_obj_g->obj_rev);
        $g_obj->is_outdated($o_obj_g->is_outdated);
        $dirty = 1;
    }
    return $dirty;
}

sub cms_post_save_entry {
    my ($cb, $app, $obj, $original) = @_;
    my $gclass = $app->model('mls_groups');
    my $group_id = $app->param('mls_group');
    
    my $g_obj;

    if ($original and $original->id) {
        if ($g_obj = $gclass->load({ blog_id => $obj->blog_id, object_id => $obj->id, object_datasource => $obj->datasource })) {
            $group_id = $g_obj->groupid;
            my $dirty = cms_post_save_entry_handle_others($app, $obj, $g_obj);
            if ($obj->basename ne $original->basename) {
                $g_obj->url($obj->permalink());
                $dirty = 1;
            }
            $g_obj->save if $dirty;
        }
        # if this is not a new object, and don't have a group, then it probably should not be in a group
        return 1;
    }

    if ($group_id) {
        # a new object, but we know to which group it belong
        $g_obj = $gclass->load({ 
            blog_id => $obj->blog_id, 
            object_id => 0, 
            object_datasource => $obj->datasource,
            groupid => $group_id,
        });
        return 1 unless $g_obj;
        $g_obj->object_id($obj->id);
        $g_obj->url($obj->permalink());
        cms_post_save_entry_handle_others($app, $obj, $g_obj);
        $g_obj->save;
    }
    else {
        # a new object, without a group relation - create group if the blog is in group
        my $g_blog = $gclass->load({ blog_id => 0, object_id => $obj->blog_id, object_datasource => 'blog' });
        # if the blog is not in group, we shouldn't do a thing
        return 1 unless $g_blog;
        my @all_blogs = $gclass->load({ blog_id => 0, object_datasource => 'blog', groupid => $g_blog->groupid });
        my @other_blogs = grep { $_->object_id != $g_blog->object_id } @all_blogs;
        my $g_obj = $gclass->new_for_entry($obj);
        $group_id = $g_obj->groupid;

        foreach my $blog (@other_blogs) {
            my $s_obj = $gclass->new_placeholder($blog->object_id, $obj->datasource, $group_id);
            $s_obj->save();
        }
    }
    return 1;
}

sub mls_diff_revision {
    my $app   = shift;
    my $q     = $app->param;
    my $group_id  = $q->param('groupid');
    my $object_id = $q->param('object');
    my $rev_from  = $q->param('rev_from');
    my $rev_to    = $q->param('rev_to');
    my $blog_id = $app->blog->id;

    my $gclass = $app->model('mls_groups');
    my @all_group = $gclass->load({ groupid => $group_id });
    my ($local) = grep { $_->blog_id == $blog_id } @all_group;
    my ($diff_obj) = grep { $_->object_id == $object_id } @all_group;

    return $app->errtrans("Invalid Request.")
        unless $local and $diff_obj and $diff_obj->object_id != 0;

    return $app->permission_denied()
        unless $app->can_do('edit_own_entry');

    my $datasource = $diff_obj->object_datasource;
    my $class = $app->model($datasource);
    my $obj = $class->load($object_id)
        or return $app->errtrans(
            'Can\'t load [_1] #[_1].', $class->class_label, $object_id
        );

    my $param = {};
    
    $rev_from =~ s/\D//g;
    $rev_to =~ s/\D//g;
    if ($rev_from > $rev_to) {
        ($rev_from, $rev_to) = ($rev_to, $rev_from);
    }

    my $obj_from = $obj->load_revision($rev_from)->[0];
    my $obj_to = $obj->load_revision($rev_to)->[0];
    my $diff = $obj_from->diff_object($obj_to);

    my $list_props =  MT->registry( list_properties => $datasource );
    require MT::Util;

    my $diff_cleaner = sub {
        my @strings = @_;
        foreach my $text (@strings) {
            $text =~ s!<\s*(?:br|p)\s*/\s*>!\n!g;
            $text =~ s!<\s*/?\s*(?:div|p)\s*>!\n!g;
            $text =~ s!(?:\s*\n)+! \n!g;
            $text = MT::Util::remove_html($text);
            $text =~ s!(\n(\s*))$!!;
        }
        return @strings;
    };

    require Text::Diff::FormattedHTML;
    my @diff_arr;
    while (my ($key, $val) = each %$diff) {
        next unless $val;
        if (@$val == 1) {
            my $flag = $val->[0]->{flag};
            next if not $flag or $flag eq 'u';
        }
        my %rec;
        $rec{title} = $app->translate("Change in <b>[_1]</b>", $key);
        my ($str1, $str2) = ($obj_from->$key(), $obj_to->$key());
        ($str1, $str2) = $diff_cleaner->($str1, $str2);
        $rec{table} = Text::Diff::FormattedHTML::diff_strings( { vertical => 1 }, $str1, $str2);
        $rec{order} = exists $list_props->{$key}->{order} ? $list_props->{$key}->{order} : 9000;
        push @diff_arr, \%rec;
    }

    @diff_arr = sort {$a->{order} <=> $b->{order}} @diff_arr;

    $param->{diff} = \@diff_arr;
    $param->{compare_css} = Text::Diff::FormattedHTML::diff_css();
    $param->{type} = $datasource;
    $param->{rev_from} = $rev_from;
    $param->{rev_to} = $rev_to;
    $param->{rev_from_created} = $obj_from->modified_on;
    $param->{rev_to_created} = $obj_to->modified_on;

    my $js
        = $app->uri
        . '?__mode=view&amp;_type='
        . $datasource
        . '&amp;id='
        . $obj->id;
    if ( $blog_id ) {
        $js .= '&amp;blog_id=' . $blog_id;
    }
    $param->{rev_js} = $js;

    local $app->{component} = "MultiLangSite";
    $app->load_tmpl( "diff_revisions.tmpl", $param );    
}

1;
