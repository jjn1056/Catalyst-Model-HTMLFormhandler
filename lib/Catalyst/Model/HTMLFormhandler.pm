package Catalyst::Model::HTMLFormhandler;

use Moose;
use Module::Pluggable::Object;

extends 'Catalyst::Model';
with 'Catalyst::Component::ApplicationAttribute';

our $VERSION = '0.001';

has 'roles' => (is=>'ro', isa=>'ArrayRef', predicate=>'has_roles');

has 'form_namespace' => (
  is=>'ro',
  required=>1,
  lazy=>1, 
  builder=>'_build_form_namespace');

  sub _default_form_namespace_part { 'Form' }

  sub _build_form_namespace {
    my $self = shift;
    return $self->_application .'::'. $self->_default_form_namespace_part;
  }

has 'form_packages' => (
  is=>'ro',
  required=>1,
  lazy=>1,
  builder=>'_build_form_packages');

  sub _build_form_packages {
    my $self = shift;
    my @forms = Module::Pluggable::Object->new(
      require => 1,
      search_path => [ $self->form_namespace ],
    )->plugins;

    return \@forms;
  }

sub build_model_adaptor {
  my ($self, $model_package, $form_package) = @_;
  my $roles = join( ',', map { "'$_'"} @{$self->roles||[]}) if $self->has_roles;

  my $package = "package $model_package;\n" . q(
  
  use Moose;
  use Moose::Util;
  use ). $form_package . q! ;
  extends 'Catalyst::Model';

  sub ACCEPT_CONTEXT {
    my ($self, $c, %args) = @_;
    my $id = '__'. ref $self;
    my %config_args = %$self;

    #If an action arg is passed and its a Catalyst::Action, make it a URL
    if(my $action = delete $args{action_from}) {
      $args{action} = ref $action ? $c->uri_for($action) : $c->uri_for_action($action);
    }

    my $no_auto_process = exists $args{no_auto_process} ?
    delete($args{no_auto_process}) : 0;

    return $c->stash->{$id} ||= do {
      my $form = $self->_build_per_request_form(%args, %config_args, ctx=>$c);
      $form->process(params=>$c->req->body_data) if
        $c->req->method=~m/post/i && \!$no_auto_process;
      return $form;
    };
  }

  sub _build_per_request_form {
    my ($self, %args) = @_;
    my $composed = Moose::Util::with_traits( '! .$form_package. q!' , (! .$roles.q!));
    my $form = $composed->new(%args);
  }

  __PACKAGE__->meta->make_immutable;

  !;

  eval $package or die $@;
}

sub construct_model_package {
  my ($self, $form_package) = @_;
  return $self->_application .'::Model'. ($form_package=~m/${\$self->_application}(::.+$)/)[0];
}

sub expand_modules {
  my ($self, $config) = @_;
  my @model_packages;
  foreach my $form_package (@{$self->form_packages}) {
    my $model_package = $self->construct_model_package($form_package);
    $self->build_model_adaptor($model_package, $form_package);
    push @model_packages, $model_package;
  }

  return @model_packages;
}

__PACKAGE__->meta->make_immutable;

=head1 NAME

Catalyst::Model::HTMLFormhandler - Proxy a directory of HTML::FormHandler forms

=head1 SYNOPSIS

    package MyApp::Model::Form;

    use Moose;
    extends 'Catalyst::Model::HTMLFormhandler';

    __PACKAGE__->config( form_namespace=>'MyApp::Form' );

And then using it in a controller:

    my $form = $c->model("Form::Email");  # Maps to MyApp::Email via MyApp:Model::Email

    # If the request is a POST, we process parameters automatically
    if($form->is_valid) {
      ...
    } else {
      ...
    }

=head1 DESCRIPTION

Assuming a project namespace 'MyApp::Form' with L<HTML::FormHandler> forms. like
the following example:

  package MyApp::Form::Email;

  use HTML::FormHandler::Moose;

  extends 'HTML::FormHandler';

  has aaa => (is=>'ro', required=>1);
  has bbb => (is=>'ro', required=>1);

  has_field 'email' => (
    type=>'Email',
    size => 96,
    required => 1);

You create a single L<Catalyst> model like this:

    package MyApp::Model::Form;

    use Moose;
    extends 'Catalyst::Model::HTMLFormhandler';

    __PACKAGE__->config( form_namespace=>'MyApp::Form' );

(Setting 'form_namespace' is optional, it defaults to the application
namespace plus "::Form" (in this example case that would be "MyApp::Form").

When you start your application it will register one model for each form
in the declared namespace.  So in the above example you should see a model
'MyApp::Model::Form::Email'.  This is a 'PerRequest' model since it does
ACCEPT_CONTEXT, it will generate a new instance of the form object once
per request scope.

You can set model configuration in the normal way, in your application general
configuration:

    package MyApp;
    use Catalyst;

    MyApp->config(
      'Model::Form::Email' => { aaa => 1000 }
    );
    
    MyApp->setup;

And you can pass additional args to the 'new' call of the form when you request
the form model:

     my $email = $c->model('Form::Email', bbb=>2000);

Additional args should be in the form of a hash, as in the above example.

The generated proxy will also add the ctx argument based on the current value of
$c, although using this may not be a good way to build well, decoupled applications.

We offer two additional bit of useful suger:

If you pass argument 'action_from' with a value of an action object or an action 
private name that will set the form action value.

By default if the request is a POST, we will process the request arguments and
return a form object that you can test for validity.  If you don't want this
behavior you can disable it by passing 'no_auto_process'.  For example:

    my $form = $c->model("Form::XXX", no_auto_process=>1)

=head1 ATTRIBUTES

This class defines the following attributes you may set via
standard L<Catalyst> configuration.

=head2 form_namespace

This is the target namespace that L<Module::Pluggable> uses to look for forms.
It defaults to 'MyApp::Form' (where 'MyApp' is you application namespace).

=head2 roles

A list of L<Moose::Role>s that get applied automatically to each form model.

=head1 SPECIAL ARGUMENTS

You may pass the following special arguments to $c->model("Form::XXX") to
influence how the form object is setup.

=head2 no_auto_process

Turns off the call to ->process when the request is a POST.

=head1 AUTHOR
 
John Napiorkowski L<email:jjnapiork@cpan.org>
  
=head1 SEE ALSO
 
L<Catalyst>, L<Catalyst::Model>, L<HTML::FormHandler>, L<Module::Pluggable>

=head1 COPYRIGHT & LICENSE
 
Copyright 2015, John Napiorkowski L<email:jjnapiork@cpan.org>
 
This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
