{
  secretsDir,
  ...
}:

{
  age.secrets.anthropic-auth-token = {
    file = secretsDir + /anthropic-auth-token.age;
    owner = "daniel";
    group = "users";
    mode = "0400";
  };
}
