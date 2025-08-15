# Azure Clean Room Big Data Samples <!-- omit from toc -->

This repository demonstrates usage of an [Azure **_Confidential Clean Room_** (**CCR**)](https://github.com/Azure/azure-cleanroom) for big data multi-party collaboration.

# Table of Contents <!-- omit from toc -->
<!--
  DO NOT UPDATE THIS MANUALLY

  The TOC is managed using the "Markdown All in One" extension.
  Use the extension commands to auto-update the TOC and section numbers.
-->
- [Overview](#overview)
- [Samples environment (per collaborator)](#samples-environment-per-collaborator)
  - [Bringing up the environment](#bringing-up-the-environment)
  - [Initializing the environment](#initializing-the-environment)
- [Setting up the clean room infrastructure](#setting-up-the-clean-room-infrastructure)
  - [Consortium creation (operator)](#consortium-creation-operator)
  - [Cleanroom environment creation (operator)](#cleanroom-environment-creation-operator)
- [Setting up the collaborators](#setting-up-the-collaborators)
  - [User identity creation (northwind, woodgrove)](#user-identity-creation-northwind-woodgrove)
  - [Invite users to the consortium (operator)](#invite-users-to-the-consortium-operator)
  - [Accepting invitations (northwind, woodgrove)](#accepting-invitations-northwind-woodgrove)
- [Publishing data](#publishing-data)
  - [KEK-DEK based encryption approach](#kek-dek-based-encryption-approach)
  - [Encrypt and upload data (northwind, woodgrove)](#encrypt-and-upload-data-northwind-woodgrove)
  - [Configure resource access for clean room (northwind, woodgrove)](#configure-resource-access-for-clean-room-northwind-woodgrove)
- [Setting up query execution](#setting-up-query-execution)
  - [Adding query to execute in the collaboration (woodgrove)](#adding-query-to-execute-in-the-collaboration-woodgrove)
  - [Agreeing upon the query for execution (northwind, woodgrove)](#agreeing-upon-the-query-for-execution-northwind-woodgrove)
- [Using the clean room](#using-the-clean-room)
  - [Executing the query (woodgrove)](#executing-the-query-woodgrove)
  - [View output (woodgrove)](#view-output-woodgrove)

# Overview

<!--TODO: Add links to corresponding readme in product repo for each capability.-->
The demo shows collaborations where one or more of the following parties come together:
  - **_Northwind_**, collaborator owning sensitive dataset(s) that can be consumed by applications inside a CCR.
  - **_Woodgrove_**, collaborator that wants to run a query over the sensitive data along with bringing in any of its own sensitive dataset(s) for consumption inside a CCR.

The following parties are additionally involved in completing the end to end demo:
  - **_Operator_**, clean room provider hosting the CCR infrastructure.

In all cases, a CCR will be executed to run the application while protecting the privacy of all ingested data, as well as protecting any confidential output. The CCR instance can be deployed by the **_operator_**, any of the collaborators or even the **_client_** without any impact on the zero-trust promise architecture.

# Samples environment (per collaborator)
All the involved parties need to bring up a local environment to participate in the sample collaborations.

## Bringing up the environment
> [!NOTE]
> Prerequisites to bring up the environment
> * Docker installed locally. Installation instructions [here](https://docs.docker.com/engine/install/).
> * PowerShell installed locally. Installation instructions [here](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell).
>
> You can also use GitHub Codespaces to create the local environment which would have the above prerequisites pre-installed.

Each party requires an independent environment. To create such an environment, open a separate powershell window for each party and run the following commands:


```powershell
$persona = # Set to one of: "operator" "northwind" "woodgrove"
```
<!-- TODO: Is it worthwhile adding a selector instead?
```powershell
function Choose-Option([string[]] $options, [string] $prompt) { 
  $displayString = "" 
  for ($i = 0; $i -lt $options.Length; $i++)
  {
    $displayString += "${i}: $($options[$i])$([environment]::NewLine)"
  } 
  $displayString += "Choose $prompt" 
  $choice=Read-Host $displayString 
  return $options[([convert]::ToInt32($choice))] 
} `
$persona = (Choose-Option -options @('operator','litware','northwind','woodgrove','client') -prompt 'persona')
```
-->

```powershell
./big-data/start-environment.ps1 -shareCredentials -persona $persona
```

This create a separate docker container for each party that contains an isolated environment, while sharing some host volumes across all of them to simplify sharing 'public' configuration details across parties.

> [!IMPORTANT]
> The command configures the environment to use a randomly generated resource group name on every invocation. To control the name, or to reuse an existing resource group, pass it in using the `-resourceGroup` parameter.
> Do not use the same resource group name for different personas.


> [!TIP]
> The`-shareCredentials` switch above enables the experience for sharing Azure credentials across the sample environments of all the parties. This brings up a credential proxy container `azure-cleanroom-samples-credential-proxy` that performs a single interactive logon at the outset, and serves access tokens to the rest of the containers from here onwards.

## Initializing the environment
> [!NOTE]
> Prerequisites to initialize the environment
> * An Azure subscription with adequate permissions to create resources and manage permissions on these resources.

Once the environment is up, execute the following command to logon to Azure:

```powershell
az login --identity
```

The command shows the subscription that will be used for resource creation by the sample scripts.

> [!TIP]
> - The command defaults to using shared credentials for logon. To use a different set of credentials for, omit the `--identity` switch and follow the device login prompts.
> - If another subscription is to be used for creating resources, execute `az account set` to select if before executing the remaining steps.


Post login, initialize the environment for executing the samples by executing the following command from the `/home/samples` directory for **every** persona:

```powershell
./scripts/initialize-environment.ps1
```

> [!IMPORTANT]
> The above script creates an Azure Storage account for OIDC usage when running for the `operator` persona. If you have a pre-configured Azure storage account for OIDC usage then supply that account name for the `operator` persona as follows:  
> ```powershell
> $storageAccountName = <name>
> ./scripts/initialize-environment.ps1 -preProvisionedOIDCStorageAccount $storageAccountName
> ```

Below is an example setup of 3 command prompts in which `start-environment` was executed before and now `initialize-environment` is about to be executed.

![alt text](command-prompts.png)

This command create the resource group and other Azure resources required for executing the samples such as a storage account, container registry and key vault (Premium).

> [!NOTE]
> All the steps henceforth assume that you are working in the `/home/samples` directory of the docker container, and commands are provided relative to that path.

<br>
<details><summary><em>Further details</em></summary>
<br>

The following Azure resources are created as part of initialization:
 - Storage Account for `northwind` and `woodgrove` environments to use as a backing store for clean room input and output.
 - Storage Account for `operator` environment to store federated identity token issuer details.
 - Storage Account with shared key access enabled for `operator` environment to use as a backing store for CCF deployments.
</details>
<br>

# Setting up the clean room infrastructure
> [!IMPORTANT]
> Ensure that you use the correct console window that corresponds to the persona for the commands mentioned below. The (`persona`) is called out in the section headings.

## Consortium creation (operator)
Collaboration using a CCR is realized and governed through a consortium created using [CCF](https://microsoft.github.io/CCF/main/overview/what_is_ccf.html) hosting a [Clean Room Governance Service (CGS)](https://github.com/Azure/azure-cleanroom/tree/main/src/governance). 

From a confidentiality perspective any of the collaborators or the *operator* can create the CCF instance without affecting the zero-trust assurances. In these samples, we assume that it was agreed upon that the *operator* will host the CCF instance. The *operator* would create the CCF instance and then invite all the collaborators as users into the consortium.

### Create the CCF instance <!-- omit from toc -->

The _operator_ (who is hosting the CCF instance) brings up a CCF instance using Confidential ACI by executing this command:

```powershell
./scripts/consortium/start-consortium.ps1
```

> [!NOTE]
> In the default sample environment, the containers for all participants have their `/home/samples/demo-resources/public` mapped to a single host directory, so details about the CCF endpoint would be available to all parties automatically once generated. If the configuration has been changed, the CCF details needs to made available in `/home/samples/demo-resources/public` of each member before executing subsequent steps.

The above script also creates the member identity for the operator of the CCF network by generating their public and private key pair. A CCF member is identified by a public-key certificate used for client authentication and command signing.

> [!IMPORTANT]
> 
> The member’s identity private key generated by the command (e.g. `operator_privk.pem`) should not be shared with anyone.
> It should be stored on a trusted device (e.g. HSM) and kept private at all times.

<br>
<details><summary><em>Azure CLI commands used</em></summary>
<br>

- `az cleanroom governance member keygenerator-sh` - generate CCF network operator certificate and keys.
- `az cleanroom ccf network create` - initialize a CCF network using `caci` (Confidential ACI) infrastructure.
- `az cleanroom ccf network transition-to-open` - activate the CCF network.
- `az cleanroom ccf provider configure` - deploy a local container hosting a client for interacting with the CCF network infrastructure.
- `az cleanroom governance client deploy` - deploy a local container hosting a client for interacting with the consortium.
</details>
<br>

## Cleanroom environment creation (operator)

### Create the cluster instance <!-- omit from toc -->

The _operator_ (who is hosting the cleanroom infra) brings up AKS cluster instance to run the Analytics workload (query). This cluster uses pods backed by Confidential ACI. Cluster creation is done by executing this command:

```powershell
./scripts/cleanroom-cluster/start-cleanroom-cluster.ps1
```

> [!NOTE]
> In the default sample environment, the containers for all participants have their `/home/samples/demo-resources/public` mapped to a single host directory, so details about the cluster endpoint would be available to all parties automatically once generated. If the configuration has been changed, the CCF details needs to made available in `/home/samples/demo-resources/public` of each user before executing subsequent steps.

# Setting up the collaborators

## User identity creation (northwind, woodgrove)
The users in the collaboration are identified by their Microsoft account (work/school or Azure account). Their login id (eg `foo@outlook.com`) is required for adding them to the collaboration.

For demo purposes you can create Microsoft accounts by visiting [outlook.com](https://outlook.com), choosing *Sign In* and the *Create one* option.
![alt text](sign-in.png)

![alt text](create-one.png)

![alt text](new-email.png)

After signing up for the accounts and choosing the email address each collaborator supplies their Microsoft account details by executing the following command:

```powershell
./scripts/consortium/share-user-identity.ps1 -email <email>
```

## Invite users to the consortium (operator)
The _operator_ (who is hosting the CCF instance) invites each user in the collaboration with the consortium using the identity details generated [above](#member-identity-creation-operator-litware-northwind-woodgrove).


```powershell
./scripts/consortium/invite-users.ps1
```

> [!NOTE]
> In the default sample environment, the containers for all participants have their `/home/samples/demo-resources/public` mapped to a single host directory, so this identity information would be available to all parties automatically once generated. If the configuration has been changed, the identity details of all other parties needs to made available in `/home/samples/demo-resources/public` of the _operator's_ environment before running the registration command above.

> [!TIP]
> To add a user to the consortium, one of the existing members is required to create a proposal for addition of the member, and a quorum of members are required to accept the same.
>
> In the default sample flows, the _operator_ is the **only** active member of the consortium at the time of inviting the members, allowing a simplified flow where the _operator_ can propose and accept all the collaborators up front. Any additional/out of band member registrations at a later time would require all the **active** members at that point to accept the new member.

## Accepting invitations (northwind, woodgrove)
Once the collaborators have been added, they now need to accept their invitation before they can participate in the collaboration.

```powershell
./scripts/consortium/accept-invitation.ps1
```

With the above steps the consortium creation that drives the creation and execution of the clean room is complete. We now proceed to preparing the datasets and making them available in the clean room.

> [!TIP]
> The same consortium can be used/reused for executing any/all the sample demos. There is no need to repeat these steps unless the collaborators have changed.

> [!NOTE]
> In the default sample environment, the containers for all participants have their `/home/samples/demo-resources/public` mapped to a single host directory, so details about the CCF endpoint would be available to all parties automatically once generated by the _operator_. If the configuration has been changed, the CCF details needs to made available in `/home/samples/demo-resources/public` of each member before executing subsequent steps.

# Publishing data
Sensitive data that any of the parties want to bring into the collaboration is ideally encrypted in a manner that ensures the key to decrypt this data will only be released to the clean room environment. This encryption is optional in case a collaborator does not want to use Client Side Encryption (CSE) for their data. This demo showcases this approach.

## KEK-DEK based encryption approach
The samples follow an envelope encryption model for encryption of data. For the encryption of the data, a symmetric **_Data Encryption Key_** (**DEK**) is generated. An asymmetric key, called the *Key Encryption Key* (KEK), is generated subsequently to wrap the DEK. The wrapped DEKs are stored in a Key Vault as a secret and the KEK is imported into an MHSM/Premium Key Vault behind a secure key release (SKR) policy. Within the clean room, the wrapped DEK is read from the Key Vault and the KEK is retrieved from the MHSM/Premium Key Vault following the secure key release [protocol](https://learn.microsoft.com/en-us/azure/confidential-computing/skr-flow-confidential-containers-azure-container-instance). The DEKs are unwrapped within the cleanroom and then used to access the storage containers.

## Encrypt and upload data (northwind, woodgrove)
It is assumed that the collaborators have had out-of-band communication and have agreed on the data sets that will be shared. In these samples, the protected data is in the form of one or more files in one or more directories at each collaborators end.

These dataset(s) in the form of files are encrypted using the [KEK-DEK](#kek-dek-based-encryption-approach) approach and uploaded into the storage account created as part of [initializing the sample environment](#initializing-the-environment). Each directory in the source dataset would correspond to one Azure Blob storage container, and all files in the directory are uploaded as blobs to Azure Storage using specified encryption mode - client-side encryption <!-- TODO: Add link to explanation of CSE. -->/ server-side encryption using [customer provided key](https://learn.microsoft.com/azure/storage/blobs/encryption-customer-provided-keys). Only one symmetric key (DEK) is created per directory (blob storage container).

```mermaid
sequenceDiagram
    title Encrypting and uploading data to Azure Storage
    actor m1 as Collaborator
    participant storage as Azure Storage

    loop every dataset folder
        m1->>m1: Generate symmetric key (DEK) per folder
        m1->>storage: Create storage container for folder
        loop every file in folder
            m1->>m1: Encrypt file using DEK
            m1->>storage: Upload to container
        end
    end
```

> [!TIP]
> Set a variable `$demo` to the name of the demo to be executed (_e.g., "**analytics**"_) - it is a required input for subsequent steps.
> ```powershell
> $demo = # Set to one of: "analytics"
> ```

The following command initializes datastores and uploads encrypted datasets required for executing the samples:

```powershell
./scripts/data/publish-data.ps1 -demo $demo
```

> [!NOTE]
> This command seeds the environment with data from external sources in some of the samples. As a result, this step which could take some time.

<!-- TODO: Switch data sources and data sinks to CSE and drop this note.-->
> [!NOTE]
> The samples currently use server-side encryption for all data sets. However the clean room infrastructure supports client side encryption as well, and client side encryption is the recommended encryption mode as it offers a higher level of confidentiality.

> [!TIP]
> <a name="MountPoints"></a>
> During clean room execution, the datasources and datasinks get presented to the application as file system mount points using the [Azure Storage Blosefuse](https://github.com/Azure/azure-storage-fuse/tree/main?tab=readme-ov-file#about) driver or the [s3fs fuse](https://github.com/s3fs-fuse/s3fs-fuse) driver.
>
> The application reads/writes data from/to these mountpoint(s) in clear text. If CSE is configured (for Azure blob storage) then under the hood, the storage system is configured to handle all the cryptography semantics, and transparently decrypts/encrypt the data using the [DEK](#61-kek-dek-based-encryption-approach) corresponding to each datastore.

<br>
<details><summary><em>Azure CLI commands used</em></summary>
<br>

- `az cleanroom datastore add` - initialize a data store. The `--encryption-mode` parameter specifies the encryption mode - `CPK` (server side encryption) or `CSE` (client side encryption).
- `az cleanroom datastore upload` - encrypt and upload local data to a data store.
</details>
<br>

## Configure resource access for clean room (northwind, woodgrove)
All the collaborating parties need to give access to the clean room so that the clean room environment can access resources in their respective tenants.

The DEKs that were created for dataset encryption as part of [data publishing](#publishing-data) are now wrapped using a KEK generated for each contract. The KEK is uploaded in Key Vault and configured with a secure key release (SKR) policy while the wrapped-DEK is saved as a secret in Key Vault.

The managed identities created earlier as part of [publishing the data](#publishing-data) are given access to resources, and a federated credential is setup for these managed identities using the CGS OIDC identity provider. This federated credential allows the clean room to obtain an attestation based managed identity access token during execution.


```powershell
./scripts/contract/grant-cleanroom-access.ps1 -demo $demo
```

> [!IMPORTANT]
> The command configures an OIDC issuer with the consortium at an Azure Active Directory Tenant level. In a setup where multiple parties belongs to the same tenant, it is important to avoid any race conditions in setting up this OIDC issuer. For such setups, it is recommended that this command should be executed by the affected parties one after the other, and not simultaneously.

# Setting up query execution
## Adding query to execute in the collaboration (woodgrove)

The following command adds details about the query to be executed within the clean room:


```powershell
./scripts/contract/add-query.ps1 -demo $demo
```

The query is picked from [query.txt](demos/analytics/query/woodgrove/query1/query.txt).

## Agreeing upon the query for execution (northwind, woodgrove)

Once the collaborating parties have finished with above steps, the query needs to be approved by each user whose dataset would get accessed by it before the clean room can execute the query. This agreement is captured formally by the **_query document_** hosted in the consortium. This is a YAML document that is generated by consuming all the dataset inputs and captures the query execution collaboration details in a formal [*clean room specification*](../../docs/cleanroomspec.md).

From a confidentiality perspective, the query document creation and proposal can be initiated by any of the collaborators (northwind or woodgrove) without affecting the zero-trust assurances. In these samples, we assume that it was agreed upon that the *consumer* undertakes this responsibility.

<!--TODO: Add query to figure out the contract ID by hitting CGS.-->
```powershell
./scripts/contract/approve-query.ps1 -demo $demo
```

# Using the clean room
## Executing the query (woodgrove)
The party interested in getting the query results (*woodgrove* in our case) can do so by running the following:

```powershell
./scripts/contract/run-query.ps1 -demo $demo
```
Note: for *client* to run the query it needs to be added as a user that does not publish any dataset or perform any query approval.

## View output (woodgrove)

The query execution output is written to the datasinks configured. Check the Azure storage container or S3 bucket to see the output files that would get generated.

