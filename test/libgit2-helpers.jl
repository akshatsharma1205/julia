# This file is a part of Julia. License is MIT: https://julialang.org/license

import Base.LibGit2: AbstractCredentials, UserPasswordCredentials, SSHCredentials,
    CachedCredentials, CredentialPayload, Payload

"""
Emulates the LibGit2 credential loop to allows testing of the credential_callback function
without having to authenticate against a real server.
"""
function credential_loop(
        valid_credential::AbstractCredentials,
        url::AbstractString,
        user::Nullable{<:AbstractString},
        allowed_types::UInt32,
        payload::CredentialPayload)
    cb = Base.LibGit2.credentials_cb()
    libgitcred_ptr_ptr = Ref{Ptr{Void}}(C_NULL)

    # Number of times credentials were authenticated against. With the real LibGit2
    # credential loop this would be how many times we sent credentials to the remote.
    num_authentications = 0

    # Emulate how LibGit2 uses the credential callback by repeatedly calling the function
    # until we find valid credentials or an exception is raised.
    err = Cint(0)
    while err == 0
        err = ccall(cb, Cint, (Ptr{Ptr{Void}}, Cstring, Cstring, Cuint, Any),
                    libgitcred_ptr_ptr, url, get(user, C_NULL), allowed_types, payload)
        num_authentications += 1

        # Check if the callback provided us with valid credentials
        if !isnull(payload.credential) && get(payload.credential) == valid_credential
            LibGit2.approve(payload)
            break
        end

        if num_authentications > 50
            error("Credential callback seems to be caught in an infinite loop")
        end
    end

    # Note: LibGit2.GitError(0) will not work if an error message has been set.
    git_error = if err == 0
        LibGit2.GitError(LibGit2.Error.None, LibGit2.Error.GIT_OK, "No errors")
    else
        LibGit2.GitError(err)
    end

    # Reject the credential when an authentication error occurs
    if git_error.code == LibGit2.Error.EAUTH
        LibGit2.reject(payload)
    end

    return git_error, num_authentications
end

function credential_loop(
        valid_credential::UserPasswordCredentials,
        url::AbstractString,
        user::Nullable{<:AbstractString}=Nullable{String}(),
        payload::CredentialPayload=CredentialPayload())
    credential_loop(valid_credential, url, user, 0x000001, payload)
end

function credential_loop(
        valid_credential::SSHCredentials,
        url::AbstractString,
        user::Nullable{<:AbstractString}=Nullable{String}(),
        payload::CredentialPayload=CredentialPayload(allow_ssh_agent=false))
    credential_loop(valid_credential, url, user, 0x000046, payload)
end

function credential_loop(
        valid_credential::AbstractCredentials,
        url::AbstractString,
        user::AbstractString,
        payload::CredentialPayload=CredentialPayload(allow_ssh_agent=false))
    credential_loop(valid_credential, url, Nullable(user), payload)
end
