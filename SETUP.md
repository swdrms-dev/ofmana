# Mise en route (une seule fois, environ 10 minutes)

Le site est hébergé sur GitHub Pages : **https://swdrms-dev.github.io/ofmana/**
Les comptes et les données sont stockés sur **Supabase** (gratuit pour démarrer).

## 1. Créer le projet Supabase

1. Va sur [supabase.com](https://supabase.com), crée un compte puis **New project**.
2. Choisis un nom (par exemple `ofmana`), un mot de passe de base de données (garde-le de côté), et une région en Europe (Paris ou Frankfurt).
3. Attends environ 2 minutes que le projet soit prêt.

## 2. Créer la base de données et ses règles de sécurité

1. Dans le menu de gauche, ouvre **SQL Editor**, puis **New query**.
2. Copie tout le contenu du fichier [`supabase/setup.sql`](supabase/setup.sql), colle-le, puis clique sur **Run**.
3. Le message « Success » doit s'afficher. Tu peux relancer ce script plus tard sans risque, il ne supprime aucune donnée.

## 3. Régler la connexion

Dans **Authentication** :

- **URL Configuration** : mets `https://swdrms-dev.github.io/ofmana/` dans **Site URL** et ajoute la même adresse dans **Redirect URLs**. C'est ce qui permet aux liens de confirmation et de mot de passe oublié de renvoyer vers ton site.
- **Sign In / Providers > Email** : laisse **Confirm email** activé. C'est indispensable : ainsi personne ne peut créer un compte avec l'email d'une de tes modèles sans avoir accès à sa boîte mail.

## 4. Relier le site au projet ✅ (déjà fait)

[`config.js`](config.js) contient l'adresse du projet et sa clé **publishable** (`sb_publishable_…`).
Cette clé est faite pour être publique. **Ne mets jamais la clé secrète (`sb_secret_…` ou `service_role`) dans le site.**

## 5. Créer ton compte admin (tout de suite)

Ouvre le site, clique sur **Créer mon compte** et inscris-toi avec ton email.
**Le premier compte créé devient l'admin.** Fais-le juste après l'étape 4, avant de partager le lien à qui que ce soit.

## 6. Donner accès à une modèle

1. Ouvre sa fiche, onglet **Accès**, renseigne son email puis clique sur **Enregistrer**.
2. Envoie-lui le lien du site. Elle clique sur **Créer mon compte** avec **ce même email**, puis confirme son adresse.
3. Son espace s'ouvre automatiquement. Le statut passe à **Compte relié** dans sa fiche.

Dans son espace, elle voit :

- son planning de contenu ;
- son chiffre d'affaires et sa part, mois par mois ;
- les tâches que tu marques **Visible par elle**, qu'elle peut cocher.

Elle ne voit jamais les autres modèles, tes notes, la prospection, les statistiques de l'agence ni les tâches internes. Ces règles sont appliquées par la base de données elle-même, pas seulement par l'interface.

## 7. Ajouter un autre admin

Dans le menu **Équipe**, saisis son email puis clique sur **Nommer admin**.

- Si la personne a déjà un compte, elle devient admin tout de suite. Elle doit simplement recharger la page.
- Sinon, l'invitation reste en attente, et elle devient admin dès qu'elle crée son compte avec cet email.

Depuis la même page, tu peux retirer les droits d'un admin ou annuler une invitation.
Tu ne peux pas retirer tes propres droits, et il reste toujours au moins un admin.

> Si tu avais lancé `setup.sql` avant l'ajout de cette page, relance-le une fois : il ajoute les nouvelles fonctions sans toucher à tes données.

## Bon à savoir

- Sur l'offre gratuite, Supabase n'envoie que quelques emails par heure (confirmation, mot de passe oublié). Si tu ajoutes beaucoup de modèles d'un coup, configure ton propre service d'envoi dans **Authentication > Emails > SMTP Settings**, par exemple Resend ou Brevo.
- Les projets gratuits sont mis en pause après 7 jours sans aucune visite. Il suffit de les relancer depuis le tableau de bord Supabase.
