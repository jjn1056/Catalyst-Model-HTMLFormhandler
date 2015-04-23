use Test::Most;
use HTTP::Request::Common;

BEGIN {
  package MyApp::Role::Test;

  use Moose::Role;

  sub TO_JSON { 'json' }

  package MyApp::Role::TestOne;

  use Moose::Role;

  sub TO_JSON_2 { 'json2' }

  package MyApp::Form::Email;

  use HTML::FormHandler::Moose;

  extends 'HTML::FormHandler';

  has aaa => (is=>'ro', required=>1);
  has bbb => (is=>'ro', required=>1);

  has_field 'email' => (
    type=>'Email',
    size => 96,
    required => 1);

  package MyApp::Form::User;

  use HTML::FormHandler::Moose;

  extends 'HTML::FormHandler';

  has_field 'name' => (
    type=>'Text',
    size => 96,
    required => 1);
}

{
  package MyApp::Model::Form;

  use Moose;
  extends 'Catalyst::Model::HTMLFormhandler';

  $INC{'MyApp/Model/Form.pm'} = __FILE__;

  package MyApp::Controller::Root;
  use base 'Catalyst::Controller';

  sub form :Local {
    my ($self, $c) = @_;
    $c->res->body('form')
  }

  sub test_process :POST Local {
    my ($self, $c) = @_;
    my $form = $c->model('Form::Email',bbb=>2000);
    Test::Most::ok $form->is_valid;
    $c->res->body($form->render)
  }

  $INC{'MyApp/Controller/Root.pm'} = __FILE__;

  package MyApp;
  use Catalyst;

  MyApp->config(
    'Controller::Root' => {namespace => ''},
    'Model::Form' => { roles => ['MyApp::Role::Test', 'MyApp::Role::TestOne'] },
    'Model::Form::Email' => { aaa => 1000 }
  );
  
  MyApp->setup;
}

use Catalyst::Test 'MyApp';

{
  my ($res, $c) = ctx_request( '/form' );
  ok my $link = $c->controller('Root')->action_for('form');
  ok my $email = $c->model('Form::Email', action_from=>$link,bbb=>2000);
  is $email->aaa, 1000;
  is $email->bbb, 2000;
  is $email->TO_JSON, 'json';
  is $email->TO_JSON_2, 'json2';
  ok $email->ctx;
  ok $email->process(params=>{email=>'jjn1056@yahoo.com'});
  ok !$email->process(params=>{email=>'jjn1056oo.com'});
  is $email->action, 'http://localhost/form';
}

{
  ok my $res = request POST '/test_process' , [email=>'jjn1056@yahoo.com'];
}

done_testing;
