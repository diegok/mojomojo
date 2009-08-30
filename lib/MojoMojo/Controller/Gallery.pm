package MojoMojo::Controller::Gallery;

use strict;
use parent 'Catalyst::Controller';

=head1 NAME

MojoMojo::Controller::Gallery - Page gallery.

=head1 SYNOPSIS

See L<MojoMojo>

=head1 DESCRIPTION

Controller for page photo galleries.

=head1 METHODS

=head2 default ( .gallery )

Show a gallery page for the current node.

=cut

sub gallery : Path {
    my ( $self, $c, $action, $page ) = @_;
    $c->stash->{template} = 'gallery.tt';
    $c->stash->{pictures} = $c->model("DBIC::Photo")->search(
        { 'attachment.page' => $c->stash->{page}->id },
        {
            page => $page || 1,
            join => [qw/attachment/],
            rows => 12,
            order_by => 'position'
        }
    );
}

=head2 by_tag ( .gallery/by_tag )

show a gallery by a given tag. Will also show photos in the
descendants of the page with the given tag.

=cut

sub by_tag : Local {
    my ( $self, $c, $tag, $page ) = @_;
    $tag = $c->model("DBIC::Tag")->search( tag => $tag )->next;
    $c->stash->{template} = 'gallery.tt';
    $c->stash->{tag}      = $tag->tag;
    my $conditions = { 'tags.tag' => $tag->tag };
    $$conditions{'attachment.page'} =
        [ map { $_->id } ( $c->stash->{page}->descendants, $c->stash->{page} ) ]
        unless length( $c->stash->{page}->path ) == 1;    # root
    $c->stash->{pictures} = $c->model("DBIC::Photo")->search(
        $conditions,
        {
            join     => [qw/attachment tags/],
            page     => $page || 1,
            rows     => 12,
            order_by => 'taken DESC'
        }
    );
}

=head2 p ( .p )

=cut

sub photo : Global {
    my ( $self, $c, $photo ) = @_;
    $photo = $c->model("DBIC::Photo")->find($photo);
    $c->stash->{photo} = $photo;
    $c->forward('inline_tags');
    $c->stash->{template} = 'gallery/photo.tt';
    $c->stash->{next}     = $photo->next_sibling;
    $c->stash->{prev}     = $photo->previous_sibling;
}

=head2 ( /p_by_tag/\d+ )

show a picture in tag gallery.

=cut

sub photo_by_tag : Global {
    my ( $self, $c, $tag, $photo ) = @_;
    $photo             = $c->model("DBIC::Photo")->find($photo);
    $c->stash->{photo} = $photo;
    $c->stash->{tag}   = $tag;
    $c->forward('inline_tags');
    $c->stash->{template} = 'gallery/photo.tt';
    $c->stash->{next}     = $photo->next_by_tag($tag);
    $c->stash->{prev}     = $photo->prev_by_tag($tag);
}

=head2 submittag ( /gallery/submittag )

Add a tag through form submit

=cut

sub submittag : Local {
    my ( $self, $c, $photo ) = @_;
    $c->forward( 'tag', [ $photo, $c->req->params->{tag} ] );
}

=head2 tag ( /.jsrpc/tag )

add a tag to a page. return list of yours and popular tags.

=cut

sub tag : Local {
    my ( $self, $c, $photo, $tagname ) = @_;
    ($tagname) = $tagname =~ m/([\w\s]+)/;
    foreach my $tag ( split m/\s/, $tagname ) {
        if (
            $tag
            && !$c->model("DBIC::Tag")->search(
                photo  => $photo,
                person => $c->user->obj->id,
                tag    => $tag
            )->next()
            )
        {
            $c->model("DBIC::Tag")->create(
                {
                    photo  => $photo,
                    tag    => $tag,
                    person => $c->user->obj->id
                }
            ) if $photo;
        }
    }
    $c->stash->{photo} = $photo;
    $c->forward( 'inline_tags', [$tagname] );
}

=head2 untag ( .gallery/untag )

Remove a tag from a page. Return a list of yours and popular tags.

=cut

sub untag : Local {
    my ( $self, $c, $photo, $tagname ) = @_;
    my $tag = $c->model("DBIC::Tag")->search(
        photo  => $photo,
        person => $c->user->obj->id,
        tag    => $tagname
    )->next();
    $tag->delete() if $tag;
    $c->stash->{photo} = $photo;
    $c->forward( 'inline_tags', [$tagname] );
}

=head2 inline_tags ( .gallery/tags )

Make a list of yours and popular tags, or just popular ones if no
user is logged in.

=cut

sub inline_tags : Local {
    my ( $self, $c, $highlight ) = @_;
    $c->stash->{template}  = 'gallery/tags.tt';
    $c->stash->{highlight} = $highlight;
    my $photo = $c->stash->{photo} || $c->req->params->{photo};
    $photo = $c->model("DBIC::Photo")->find($photo) unless ref $photo;
    $c->stash->{photo} = $photo;
    if ( $c->user_exists ) {
        my @tags = $photo->others_tags( $c->user->obj->id );
        $c->stash->{others_tags} = [@tags];
        @tags                    = $photo->user_tags( $c->user->obj->id );
        $c->stash->{taglist}     = ' ' . join( ' ', map { $_->tag } @tags ) . ' ';
        $c->stash->{tags}        = [@tags];
    }
    else {
        $c->stash->{others_tags} = [ $photo->others_tags(undef) ];
    }
}

=head2 description ( .gallery/description )

AJAX method for updating picture descriptions inline.

=cut

sub description : Local {
    my ( $self, $c, $photo ) = @_;
    my $img = $c->model("DBIC::Photo")->find($photo);
    if ( $c->req->param('update_value') ) {
        $img->description( $c->req->param('update_value') );
        $img->update;
    }
    $c->res->body( $img->description );
}

=head2 title ( .gallery/title )

AJAX method for updating picture titles inline.

=cut

sub title : Local {
    my ( $self, $c, $photo ) = @_;
    my $img = $c->model("DBIC::Photo")->find($photo);
    if ( $c->req->param('update_value') ) {
        $img->title( $c->req->param('update_value') );
        $img->update;
    }
    $c->res->body( $img->title );
}

sub tags : Local {
    my ( $self, $c, $tag ) = @_;
    $c->stash->{tags} = [ $c->model("DBIC::Tag")->by_photo ];
    my $cloud = HTML::TagCloud->new();
    foreach my $tag ( @{ $c->stash->{tags} } ) {
        $cloud->add(
            $tag->tag,
            $c->req->base
                . $c->stash->{path}
                . '.gallery/by_tag/'
                . $tag->tag . '/'
                . $tag->photo,
            $tag->refcount
        );
    }
    $c->stash->{cloud}    = $cloud;
    $c->stash->{template} = 'gallery/cloud.tt';
}

=head1 AUTHOR

Marcus Ramberg <mramberg@cpan.org>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
