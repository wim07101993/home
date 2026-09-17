Not read by tofu -- a note for whoever opens this directory.

Org `Home` is split one project per application, so a grant can be per app:

    Score    score-api, score-web-app        score_editor, score_viewer
    home     home assistant                  family
    photos   immich                          family
    drive    drive                           family
    keuken   transaction-importer, web-app   family
    memo     memo                            family

Every project sets has_project_check = true, which is what makes the split
worth anything: without a grant to that project, a user cannot get a token for
its apps at all.

That is a behaviour change for keuken, which had the check off -- everyone in
the org could authenticate. After the rebuild, kitchen-owl users need an
explicit grant like everywhere else.
