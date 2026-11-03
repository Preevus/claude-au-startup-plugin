#!/usr/bin/env python3
"""Build Australian Pty Ltd incorporation documents from a JSON config.

Usage: python build_pack.py config.json OUTDIR [--post-registration]

Produces (HTML + DOCX): Constitution, Incorporation Pack, and optionally the
Post-Registration Pack. Any value missing from the config is rendered as a
[PLACEHOLDER] so the output is safe to use as a blank template.
These are general drafts only and must be reviewed by a lawyer before use.
"""
import html
import json
import os
import subprocess
import sys


def E(s):
    return html.escape(str(s), quote=False)


class Cfg:
    def __init__(self, d):
        self.d = d

    def g(self, key, ph=None):
        v = self.d.get(key)
        if v in (None, "", []):
            return "[" + (ph or key.replace("_", " ").upper()) + "]"
        return v

    def has(self, key):
        return bool(self.d.get(key))


class Doc:
    def __init__(self, title):
        self.title = title
        self.parts = []

    def h1(self, t):
        self.parts.append("<h1>%s</h1>" % E(t))

    def h2(self, t):
        self.parts.append("<h2>%s</h2>" % E(t))

    def p(self, t):
        self.parts.append("<p>%s</p>" % E(t))

    def note(self, t):
        self.parts.append("<p><em>Drafting note: %s</em></p>" % E(t))

    def items(self, lst):
        self.parts.append("<ul>%s</ul>" % "".join("<li>%s</li>" % E(i) for i in lst))

    def table(self, rows, header=None):
        out = ["<table>"]
        if header:
            out.append("<tr>%s</tr>" % "".join("<th>%s</th>" % E(h) for h in header))
        for r in rows:
            out.append("<tr>%s</tr>" % "".join("<td>%s</td>" % E(c) for c in r))
        out.append("</table>")
        self.parts.append("".join(out))

    def sig(self, name, role, date=True):
        self.p("Signature: ______________________________")
        self.p("%s, %s" % (name, role))
        if date:
            self.p("Date: [DD/MM/YYYY]")

    def html(self):
        return "<html><head><meta charset='utf-8'><title>%s</title></head><body>%s</body></html>" % (
            E(self.title), "\n".join(self.parts))


def full(d):
    return ("%s %s" % (d.get("given", "[GIVEN NAMES]"), d.get("family", "[FAMILY NAME]"))).strip()


def company(c):
    return "%s Pty Ltd" % c.g("company_name", "COMPANY NAME")


def directors(c):
    return c.d.get("directors") or [{}, {}]


def holders(c):
    return c.d.get("shareholders") or [{}, {}]


def holder_name(h):
    return h.get("name", "[SHAREHOLDER NAME]")


def share_total(c):
    return c.d.get("total_shares", "[TOTAL SHARES]")


# ---------------------------------------------------------------- constitution
def constitution(c):
    d = Doc("Constitution of %s" % company(c))
    co, acn = company(c), c.g("acn", "ACN")
    pct = str(c.d.get("vote_threshold_pct", "[51]"))
    maxd = c.d.get("max_directors", "[MAX DIRECTORS]")
    opt = c.d.get("option") or {}
    d.h1("CONSTITUTION of %s" % co.upper())
    d.p("ACN %s" % acn)
    d.note("Draft only. Replace remaining [square brackets], delete drafting notes, and have a lawyer review "
           "this constitution (especially clauses 4.5, 7.5 and 14) before it is adopted or lodged.")

    d.h2("PART A: PRELIMINARY")
    d.h2("1. Interpretation")
    d.p("1.1 In this Constitution, unless the context requires otherwise:")
    for t in ["(a) \u201cAct\u201d means the Corporations Act 2001 (Cth);",
              "(b) \u201cCompany\u201d means %s ACN %s;" % (co, acn),
              "(c) \u201cDirector\u201d means a person holding office as a director of the Company, and includes an Alternate Director acting in that capacity;",
              "(d) \u201cAlternate Director\u201d means a person appointed under clause 21;",
              "(e) \u201cMember\u201d means a person entered in the register of members as the holder of a Share;",
              "(f) \u201cFounding Member\u201d means each Member named in Schedule 2 as at the date this Constitution was adopted;",
              "(g) \u201cShare\u201d means a share in the capital of the Company;",
              "(h) \u201cSpecial Resolution\u201d has the meaning given in the Act; and",
              "(i) \u201cSchedule\u201d means a schedule to this Constitution."]:
        d.p(t)
    for t in ["1.2 Words and expressions defined in the Act have the same meaning in this Constitution unless the context requires otherwise.",
              "1.3 Unless the context requires otherwise, the singular includes the plural and the reverse, and a reference to any gender includes all genders.",
              "1.4 A reference to legislation includes that legislation as amended or replaced from time to time.",
              "1.5 Headings are for convenience only and do not affect interpretation."]:
        d.p(t)
    d.h2("2. Replaceable rules")
    d.p("2.1 The replaceable rules in the Act do not apply to the Company. The Company is governed by this Constitution and by the Act.")
    d.p("2.2 If this Constitution is inconsistent with a provision of the Act that cannot be excluded or modified, the Act prevails to the extent of the inconsistency.")

    d.h2("PART B: SHARES")
    d.h2("3. Issue of Shares")
    d.p("3.1 Subject to the Act and this Constitution (including clause 4), the Directors may issue Shares, grant options over Shares, and settle the terms on which Shares are issued, at the times, to the persons and for the consideration they decide.")
    d.p("3.2 The Company may issue Shares of any class, including ordinary Shares, preference Shares (including redeemable preference Shares), partly paid Shares and bonus Shares.")
    d.p("3.3 The rights and restrictions attaching to each class of Share are set out in Schedule 1 or, for a class created later, in the terms of its issue.")
    d.p("3.4 The Company may issue preference Shares, or convert ordinary Shares into preference Shares, only if the rights attaching to them on each of the following have first been approved by Special Resolution: (a) repayment of capital; (b) participation in surplus assets and profits; (c) cumulative or non-cumulative dividends; (d) voting; and (e) priority of payment of capital and dividends relative to other Shares or classes.")
    d.p("3.5 The Company may convert preference Shares into ordinary Shares, and may consolidate or subdivide its Shares, in the manner permitted by the Act.")

    d.h2("4. Offers to existing Members and protection against dilution")
    d.p("4.1 Before the Directors issue Shares of a class, they must first offer those Shares to the existing holders of Shares of that class, as nearly as practicable in proportion to their existing holdings.")
    d.p("4.2 An offer under clause 4.1 must be made by written notice stating the number of Shares offered, the issue price, and the period (not less than 14 days) for which the offer remains open.")
    d.p("4.3 Shares not taken up under an offer may be issued by the Directors to any person on terms no more favourable than those offered to Members, subject to clause 4.5.")
    d.p("4.4 The Members may waive the requirements of clause 4.1 for a particular issue only if every Member entitled to the offer agrees in writing.")
    if c.d.get("anti_dilution", True):
        d.p("4.5 While a Founding Member holds Shares, the Company must not, without the prior written consent of each Founding Member: (a) issue Shares, options or convertible securities; (b) create or issue a class of Shares ranking ahead of or equally with the Shares held by the Founding Members; or (c) reduce or alter its share capital, in each case in a way that would reduce a Founding Member\u2019s percentage of the total Shares or of the total votes, other than an issue where each Founding Member was first offered, and had the opportunity to take up, its full pro rata entitlement under clause 4.1.")
        d.note("Anti-dilution wording is a first draft of the founders\u2019 intent. A lawyer should confirm it works with the voting threshold in clause 14.2 and any shareholders\u2019 agreement.")
    if opt:
        d.p("4.6 Despite clauses 4.1 to 4.5, the Company may issue up to %s Shares to %s on exercise of the option granted under the option deed between the Company, the Founding Members and %s (Option Deed), at the price and on the terms in the Option Deed, if the option is exercised on or before %s. Each Founding Member consents to that issue." % (
            opt.get("shares", "[OPTION SHARES]"), opt.get("holder", "[OPTION HOLDER]"), opt.get("holder", "[OPTION HOLDER]"), opt.get("expiry", "[EXPIRY DATE]")))
        d.note("The option price (described as the value of retained earnings) is not yet defined. It should be settled in the Option Deed before this clause is relied on.")

    d.h2("5. Register, trusts and certificates")
    d.p("5.1 The Company must keep a register of Members in accordance with the Act. A Member is not required to be a Director, and a Director is not required to be a Member.")
    d.p("5.2 Except as required by law, the Company is not required to recognise any person as holding a Share on trust or to recognise any interest in a Share other than the absolute right of the registered holder.")
    d.p("5.3 A Member who holds Shares as trustee or nominee for a corporation must, within one month of acquiring the Shares, give the Company written notice of the beneficial owner\u2019s name and Australian Company Number.")
    d.p("5.4 The Company must issue a certificate (or other evidence of title permitted by the Act) to each Member on request without charge. For jointly held Shares, delivery to one joint holder is delivery to all. A defaced, lost or destroyed certificate may be replaced on the terms the Directors reasonably require.")

    d.h2("6. Partly paid Shares, calls and forfeiture")
    for t in ["6.1 The Directors may make calls on Members for money unpaid on their partly paid Shares, in line with the terms of issue. A call is made when the Directors\u2019 resolution authorising it is passed, and may be payable by instalments.",
              "6.2 Each Member must pay the amount called at the time and place specified in a notice of not less than 14 days. Joint holders are jointly and severally liable for calls on their Shares.",
              "6.3 The Directors may revoke or postpone a call, differentiate between Members as to the amount and timing of calls at the time of issue, and accept payment of uncalled amounts in advance.",
              "6.4 Interest accrues on an unpaid call from the due date to the date of payment at the rate set by the Directors, not exceeding 8% per annum. The Directors may waive interest in whole or in part.",
              "6.5 If a call remains unpaid, the Directors may serve a notice requiring payment of the unpaid amount and accrued interest by a date at least 14 days after service, stating that the Shares are liable to be forfeited if payment is not made.",
              "6.6 If the notice is not complied with, the Directors may by resolution forfeit the Shares. Forfeiture includes dividends declared on the Shares and not yet paid.",
              "6.7 Forfeited Shares may be sold or otherwise disposed of on terms the Directors decide, and the forfeiture may be cancelled before disposal. A former holder remains liable for money owing at the date of forfeiture until it is paid in full.",
              "6.8 A written statement by a Director that a Share was forfeited on a stated date is prima facie evidence of that fact. The title of a person to whom a forfeited Share is transferred is not affected by any irregularity in the forfeiture or sale."]:
        d.p(t)

    d.h2("7. Transfer of Shares")
    for t in ["7.1 A Member may transfer Shares by a written instrument of transfer in a form approved by the Directors or in any usual form, signed by or for the transferor and the transferee.",
              "7.2 The transferor remains the holder until the transferee\u2019s name is entered in the register of Members.",
              "7.3 The instrument of transfer must be lodged at the Company\u2019s registered office with the share certificate (if any), any reasonable fee set by the Directors, and any other evidence the Directors reasonably require.",
              "7.4 Subject to clause 7.5, the Directors may refuse or delay registration of a transfer where the Shares are not fully paid, where the Company has a lien over them, or where the transfer would breach this Constitution or the law. The Directors may also suspend registration of transfers for periods not exceeding 30 days in any calendar year."]:
        d.p(t)
    if c.d.get("shotgun", True):
        d.p("7.5 If there are two Founding Members, either of them (the Offeror) may give the other (the Recipient) a written notice (Shotgun Notice) stating a price per Share (Shotgun Price) at which the Offeror will either buy all of the Recipient\u2019s Shares or sell all of its own Shares.")
        for t in ["(a) Within 30 days after receiving the Shotgun Notice, the Recipient must give written notice electing either to sell all its Shares to the Offeror, or to buy all of the Offeror\u2019s Shares, at the Shotgun Price.",
                  "(b) A Recipient that does not elect within that period is taken to have elected to sell all its Shares to the Offeror at the Shotgun Price.",
                  "(c) Completion must occur within 30 days after the election (or deemed election), on payment of the price in cleared funds against delivery of signed transfers. The Directors must register a transfer made under this clause despite clause 7.4.",
                  "(d) A Founding Member may not give a Shotgun Notice within 12 months after an earlier Shotgun Notice that was not completed."]:
            d.p(t)
        d.note("This mechanism assumes two Founding Members. If more than two Members hold Shares (for example after an option is exercised), the mechanics need to be settled by a lawyer, ideally in a shareholders\u2019 agreement. Where Founding Members hold through companies or nominees, the notice should bind the ultimate holders.")
    else:
        d.p("7.5 [Insert restricted transfer or first refusal clause, or delete.]")

    d.h2("8. Transmission of Shares")
    d.p("8.1 If a sole Member dies, the Company will recognise only the legal personal representative as having any entitlement to the Shares. If a joint holder dies, the Company will recognise only the surviving holder(s). The estate of a deceased Member remains liable for amounts owing on the Shares.")
    d.p("8.2 A person who becomes entitled to Shares by reason of a Member\u2019s death, bankruptcy or mental incapacity may, on providing the evidence the Directors reasonably require, elect by signed written notice to be registered as the holder or to nominate a transferee. The Company must then register that person or the nominee, subject to clause 7.4.")
    d.p("8.3 Until registered, a person entitled under clause 8.2 has the rights of the Member, except that they may not vote at a meeting unless the Directors have first accepted their entitlement. This clause is subject to the Bankruptcy Act 1966 (Cth).")
    d.h2("9. Lien")
    d.p("9.1 The Company has a first lien on each partly paid Share for unpaid calls and amounts payable in respect of that Share, and on dividends payable on it. The Directors may waive the lien in whole or in part.")
    d.p("9.2 The Company may sell Shares subject to a lien in the manner the Directors decide if the amount secured is presently payable and the Company has given the holder at least 14 days\u2019 written notice demanding payment.")
    d.p("9.3 The sale proceeds must be applied first to the amount secured that is presently payable, and any balance paid to the person entitled to the Shares at the date of sale. The purchaser need not see to the application of the proceeds, and their title is not affected by any irregularity in the sale.")

    d.h2("PART C: MEETINGS OF MEMBERS")
    d.h2("10. Calling meetings")
    d.p("10.1 A Director may call a meeting of Members. Members may also require or call a meeting as permitted by the Act.")
    d.p("10.2 The Company must give at least 21 days\u2019 written notice of a meeting of Members, in the manner required by the Act. Shorter notice is valid if it is agreed by all Members entitled to vote.")
    d.p("10.3 If a meeting is adjourned for one month or more, fresh notice of the resumed meeting must be given.")
    d.p("10.4 A meeting of Members may be held at one or more physical venues, by technology, or both, in the manner permitted by the Act, provided that Members as a whole have a reasonable opportunity to participate.")
    d.h2("11. Quorum")
    d.p("11.1 A quorum for a meeting of Members is Members holding at least %s%% of the votes attaching to all Shares entitled to vote, present in person, by proxy, by attorney or, for a corporate Member, by representative." % pct.strip("[]") if isinstance(pct, str) else "11.1 A quorum is [QUORUM].")
    d.p("11.2 If a quorum is not present within 30 minutes after the scheduled start, the meeting is adjourned to the date, time and place the Directors specify or, if none is specified, to the same time and place one week later. If a quorum is not present within 30 minutes of the resumed meeting, it is dissolved.")
    d.h2("12. Chair")
    d.p("12.1 The Directors may elect a Director to chair meetings of Members. If no chair has been elected or the elected chair is absent or declines to act, the Directors present must elect a chair, failing which the Members present must elect one of their number.")
    d.p("12.2 The chair must adjourn the meeting if the Members present with a majority of votes direct them to do so. The chair does not have a casting vote.")
    d.h2("13. Proxies, attorneys and representatives")
    d.p("13.1 A Member entitled to vote may appoint a proxy, who need not be a Member, by written notice to the Company. The appointment may specify the proportion or number of votes the proxy may exercise. A Member entitled to cast two or more votes may appoint two proxies; if no proportion is specified, each may exercise half the votes, disregarding fractions.")
    d.p("13.2 To be effective, a proxy appointment (and any authority under which it was signed) must be received by the Company at least 48 hours before the meeting.")
    d.p("13.3 A vote cast by a proxy is valid despite the death or incapacity of the appointing Member or revocation of the appointment, unless the Company received written notice before the meeting started or resumed.")
    d.p("13.4 A corporate Member may appoint a representative in the manner permitted by the Act.")
    d.h2("14. Voting")
    d.p("14.1 Subject to the rights and restrictions attaching to any class, each Member has one vote for each Share held, both on a show of hands and on a poll.")
    d.p("14.2 An ordinary resolution of Members is passed only if Members holding at least %s%% of the votes attaching to all Shares entitled to vote (not only those present) vote in favour, unless the Act or this Constitution requires a greater majority." % pct.strip("[]"))
    d.note("A Special Resolution is governed by the Act (at least 75% of votes cast) and cannot be lowered by the constitution. With two equal Founding Members, a threshold above 50% means both must agree, so the shotgun clause (7.5) is the main deadlock-breaking tool.")
    d.p("14.3 Where Shares are jointly held and more than one joint holder votes, only the vote of the holder named first in the register counts.")
    d.p("14.4 An objection to a person\u2019s right to vote may be raised only at the meeting, and the chair\u2019s decision is final. A declaration by the chair of the result of a show of hands is conclusive. A poll may be demanded as permitted by the Act, except on the election of the chair or the question of adjournment, and must be taken as the chair directs.")
    d.p("14.5 The chair does not have a second or casting vote.")
    d.h2("15. Resolutions without a meeting")
    d.p("15.1 The Members may pass a resolution without a meeting if all Members entitled to vote sign a document stating they are in favour of the resolution. Separate counterparts may be used. If the Company has one Member, that Member may record a resolution in writing and sign it.")
    d.p("15.2 The resolution is passed when the last Member signs.")
    d.p("15.3 Minutes of meetings and resolutions of Members must be kept in accordance with the Act.")

    d.h2("PART D: DIRECTORS")
    d.h2("16. Number of Directors")
    d.p("16.1 The Company must have at least one Director and may have up to %s Directors, or such other number as the Members determine by resolution." % maxd)
    d.p("16.2 If the Company has more than one Director, at least one Director must ordinarily reside in Australia, as required by the Act.")
    d.h2("17. Appointment and removal")
    d.p("17.1 The Members may appoint any person as a Director by resolution at a general meeting or by written resolution. The Directors may also appoint a person to fill a casual vacancy or as an addition to the Directors, but that person holds office only until the next general meeting unless confirmed by the Members.")
    d.p("17.2 The Members may by resolution remove a Director from office and appoint another person in their place.")
    d.p("17.3 A Director may resign by written notice to the Company. A Director ceases to hold office if they become disqualified from managing a corporation under the Act, die, or become bankrupt or of unsound mind.")
    d.p("17.4 Every appointment, removal or resignation must be in writing, and the Company must notify ASIC within the time and in the manner required by the Act.")
    d.h2("18. Director identification numbers")
    d.p("18.1 Each Director and Alternate Director must obtain a Director identification number within the time required by the Act, and provide it to the Company on request.")
    d.h2("19. Powers of Directors")
    d.p("19.1 The business of the Company is managed by or under the direction of the Directors, who may exercise all powers of the Company except those the Act or this Constitution require to be exercised by the Members.")
    d.p("19.2 Any two Directors (or one Director if there is only one) may sign, draw, accept, endorse or otherwise execute a negotiable instrument on behalf of the Company, unless the Directors decide on a different method.")
    d.p("19.3 The Directors may appoint attorneys or agents of the Company and delegate powers to them on the terms they decide.")
    d.h2("20. Managing Director and committees")
    d.p("20.1 The Directors may appoint one or more of themselves as Managing Director for the period and on the terms (including remuneration) they decide, may confer on the Managing Director any of their powers, and may vary or revoke the appointment or those powers. A Managing Director ceases to hold that office on ceasing to be a Director.")
    d.p("20.2 The Directors may delegate any of their powers to a committee of Directors. A committee must exercise delegated powers in accordance with any directions of the Directors, and the exercise of those powers is treated as an exercise by the Directors. Any delegation must be recorded in the Company\u2019s minute book.")
    d.h2("21. Alternate Directors")
    d.p("21.1 With the approval of the other Directors, a Director may appoint a person as an Alternate Director for a specified period to exercise some or all of the appointing Director\u2019s powers.")
    d.p("21.2 On request of the appointing Director, the Company must give the Alternate Director notice of Directors\u2019 meetings. The exercise of a power by an Alternate Director is as effective as if exercised by the appointing Director. The appointing Director may end the appointment at any time by written notice.")
    d.h2("22. Interests of Directors")
    d.p("22.1 A Director who has a material personal interest in a matter must disclose the nature and extent of the interest to the other Directors in accordance with the Act.")
    d.p("22.2 Subject to the Act, a Director who has made that disclosure may vote on the matter, be counted in the quorum, enter into the relevant contract with the Company, and retain benefits under it. The Company may not avoid the contract only because of the Director\u2019s interest.")
    d.h2("23. Remuneration and expenses")
    d.p("23.1 Directors are entitled to the remuneration the Company determines by resolution. The Company may reimburse Directors for reasonable travel and other expenses properly incurred in attending meetings or carrying out the Company\u2019s business.")

    d.h2("PART E: DIRECTORS\u2019 MEETINGS")
    d.h2("24. Calling and conduct of meetings")
    d.p("24.1 A Director may call a meeting of Directors by giving reasonable notice to each other Director. Meetings may be held in person or by technology that allows each Director to participate.")
    d.p("24.2 The Directors may elect a Director to chair their meetings and decide how long they hold that office. The chair does not have a casting vote.")
    d.h2("25. Quorum and decisions")
    d.p("25.1 A quorum for a meeting of Directors is two Directors (or one, if there is only one Director). A resolution is passed by a majority of the Directors present and entitled to vote.")
    d.note("With two Directors and no casting vote, both Directors must agree. This matches the intent that neither founder can act alone, but it can produce deadlock; clause 7.5 provides the exit.")
    d.p("25.2 If the Company has only one Director, that Director may pass a resolution by recording it in writing, and the written record is treated as a resolution passed at a meeting of Directors.")
    d.h2("26. Circular resolutions and minutes")
    d.p("26.1 The Directors may pass a resolution without a meeting if all Directors entitled to vote sign a document stating they are in favour of the resolution. Separate counterparts may be used if the wording is identical. The resolution is passed when the last Director signs.")
    d.p("26.2 Minutes of all meetings and resolutions of Directors must be kept in accordance with the Act.")

    d.h2("PART F: GENERAL")
    d.h2("27. Secretary")
    d.p("27.1 The Directors may appoint one or more secretaries (and assistant secretaries) on the terms, including remuneration, they decide. A Director may act as secretary.")
    d.h2("28. Dividends")
    d.p("28.1 The Directors may resolve to pay a dividend, and may fix its amount, the time for payment and the method of payment, but a dividend may be paid only if the Company meets the requirements of the Act.")
    d.p("28.2 Subject to the rights attaching to any class of Share, dividends may be paid in cash, by issuing Shares or options, or by transferring assets, and may be paid by cheque, electronic transfer or other method the Directors decide to the Member\u2019s registered details.")
    d.p("28.3 The Directors may deduct from any dividend amounts presently payable by the Member to the Company in relation to Shares. Interest is not payable on a dividend.")
    d.h2("29. Access to records")
    d.p("29.1 The Directors, or the Company by resolution at a general meeting, may authorise a Member to inspect the books of the Company. Subject to the Act, Members have no other right to inspect the books.")
    d.h2("30. Indemnity and insurance")
    d.p("30.1 To the extent permitted by the Act, the Company indemnifies each current and former officer (and, if the Directors so decide, each auditor or agent) against liability incurred in that capacity, including legal costs, except where the liability arises from a wilful breach of duty, conduct involving a lack of good faith, or a liability to the Company or a related body corporate.")
    d.p("30.2 The Company may, to the extent permitted by the Act, pay premiums for insurance for any officer against liabilities incurred in that capacity.")
    d.h2("31. Notices")
    d.p("31.1 A notice may be given to a Member or Director personally, by post, by email to the address the person has nominated, or by any other method permitted by the Act. A notice sent by post is taken to be received three business days after posting, and a notice sent by email is taken to be received on the next business day after it is sent, unless the sender is notified of non-delivery.")
    d.h2("32. Signing documents")
    d.p("32.1 Where this Constitution requires a document to be signed, it may be signed by hand or electronically, in each case in a manner permitted by the Act.")
    d.h2("33. Winding up")
    d.p("33.1 On winding up, and subject to the rights attaching to any class of Share and to the Act, surplus assets are to be distributed among Members in proportion to the amounts paid on their Shares. A liquidator may, with the approval of a Special Resolution, distribute assets in kind.")
    d.h2("34. Amendment")
    d.p("34.1 This Constitution may be modified or repealed only by Special Resolution of the Members.")

    d.h1("SCHEDULE 1: SHARE CLASSES")
    d.table([[c.d.get("share_class_code", "[CLASS CODE]") + " (" + c.d.get("share_class_title", "[CLASS TITLE, e.g. Ordinary]") + ")",
              "Yes", "Yes (one vote per Share)", "Yes, in proportion to Shares held", "Participates in surplus", "No"]],
            ["Class", "Attend meetings", "Vote", "Dividends", "Return of capital and surplus on winding up", "Redeemable"])
    d.h1("SCHEDULE 2: AGREEMENT OF INITIAL MEMBERS")
    d.p("Each person named below consents to becoming a Member of the Company, agrees to be bound by this Constitution, and agrees to take up the Shares stated against their name at the issue price stated.")
    rows = []
    for h in holders(c):
        who = holder_name(h) + (" (ACN %s)" % h.get("acn", "[ACN]") if h.get("type") == "company" else "")
        rows.append(["Signature: ____________  Full name: %s  Address: %s  Date: [DD/MM/YYYY]" % (who, h.get("address", "[ADDRESS]")),
                     str(h.get("shares", "[NUMBER]")), c.d.get("share_class_code", "[CLASS]"), c.d.get("price_per_share", "$[ISSUE PRICE]")])
    d.table(rows, ["Member details and signature", "Number of Shares", "Class", "Issue price per Share"])
    return d


# ------------------------------------------------------------ incorporation pack
def incorporation(c):
    d = Doc("Incorporation Document Pack: %s" % company(c))
    co = company(c)
    ds, hs = directors(c), holders(c)
    office = c.g("registered_office", "REGISTERED OFFICE ADDRESS")
    d.h1("COMPANY INCORPORATION DOCUMENT PACK: %s" % co.upper())
    d.p("Proprietary company limited by shares. Draft prepared for self-lodgement with ASIC.")
    d.note("The official ASIC application (Form 201) must be completed on ASIC\u2019s current form. Section 1 is a data sheet to collect the information needed to complete it. Have a lawyer or compliance team review before use.")
    d.h2("Open items before lodgement")
    items = c.d.get("open_items") or ["Replace every remaining [square bracket] item",
                                      "Each director to obtain a Director ID (not yet obtained unless entered below)"]
    d.items(items)

    d.h1("1. REGISTRATION INFORMATION SHEET")
    d.h2("A. Lodgement contact")
    d.table([["Registered agent number (if any)", "N/A (self-lodged)"],
             ["Contact name", c.g("lodgement_contact", "CONTACT NAME")],
             ["Phone", c.g("lodgement_phone", "PHONE")], ["Email", c.g("lodgement_email", "EMAIL")],
             ["Postal address", c.g("lodgement_postal", "POSTAL ADDRESS")]])
    d.h2("B. Company details")
    d.table([["State or territory of registration", c.g("state", "STATE")],
             ["Proposed company name", co],
             ["Name reservation number (if any)", c.d.get("name_reservation", "N/A")],
             ["Name identical to a registered business name?", c.d.get("name_clash", "[CONFIRM after name check: Yes / No]")],
             ["Company type and class", "Proprietary company limited by shares"],
             ["Special purpose", "None"], ["Governance", "Constitution adopted"]])
    d.h2("C. Registered office and principal place of business")
    d.table([["Registered office address", office],
             ["Does the company occupy the premises?", c.d.get("company_occupies", "No (see occupier\u2019s consent, Section 5)")],
             ["Name of occupier", c.g("office_occupier", "OCCUPIER NAME")],
             ["Occupier\u2019s written consent obtained?", "[Yes / No] (Section 5)"],
             ["Principal place of business", c.d.get("principal_place", "Same as registered office")]])
    d.h2("D. Officeholders")
    hdr = ["Item"] + ["Director %d" % (i + 1) for i in range(len(ds))]
    rows = [["Office held"] + ["Director" for _ in ds],
            ["Family name"] + [x.get("family", "[FAMILY NAME]") for x in ds],
            ["Given names"] + [x.get("given", "[GIVEN NAMES]") for x in ds],
            ["Former names"] + [x.get("former", "[FORMER NAMES or N/A]") for x in ds],
            ["Residential address"] + [x.get("address", "[ADDRESS]") for x in ds],
            ["Date of birth"] + [x.get("dob", "[DD/MM/YYYY]") for x in ds],
            ["Place of birth"] + [x.get("pob", "[TOWN/CITY, STATE/COUNTRY]") for x in ds],
            ["Director ID"] + [x.get("director_id", "[DIRECTOR ID]") for x in ds],
            ["Resides in Australia?"] + [x.get("resides", "Yes") for x in ds]]
    d.table(rows, hdr)
    d.note("At least one director must ordinarily reside in Australia. No secretary is appointed unless added. Handle dates of birth and Director IDs as sensitive data.")
    d.h2("E. Share structure")
    d.table([[c.d.get("share_class_code", "[ORD]"), c.d.get("share_class_title", "[TITLE]"), str(share_total(c)),
              c.d.get("total_paid", "$[AMOUNT]"), c.d.get("total_unpaid", "$0")]],
            ["Class code", "Full title", "Total shares", "Total paid", "Total unpaid"])
    d.p("Any shares issued other than for cash? %s" % c.d.get("non_cash", "[Yes / No]"))
    d.h2("F. Members")
    rows = [[holder_name(h), "Co." if h.get("type") == "company" else "Ind.", h.get("acn", "N/A"), h.get("address", "[ADDRESS]"),
             c.d.get("share_class_code", "[CLASS]"), str(h.get("shares", "[NO.]")), c.d.get("price_per_share", "$[PRICE]"),
             c.d.get("fully_paid", "[Y/N]")] for h in hs]
    d.table(rows, ["Member", "Type", "ACN", "Address", "Class", "Shares", "Price per share", "Fully paid?"])
    for h in hs:
        if h.get("nominee_for"):
            d.note("%s holds for %s. Confirm whether it holds as nominee or trustee (constitution clause 5.3 requires notice of the beneficial owner)." % (holder_name(h), h["nominee_for"]))
    d.h2("G. Applicant")
    d.table([["Name of applicant", c.g("applicant", "APPLICANT NAME")], ["Capacity", c.d.get("applicant_capacity", "Individual")],
             ["Name of signatory", c.g("applicant", "SIGNATORY NAME")], ["Date signed", "[DD/MM/YYYY]"]])

    d.h1("2. CONSENT TO ACT AS DIRECTOR")
    for x in ds:
        d.h2(full(x))
        d.p("To the Directors, %s, %s" % (co, office))
        d.p("I consent to act as a director of the company and provide the following information:")
        d.table([["Full name", full(x)], ["Residential address", x.get("address", "[ADDRESS]")],
                 ["Date of birth", x.get("dob", "[DD/MM/YYYY]")], ["Place of birth", x.get("pob", "[TOWN/CITY, STATE/COUNTRY]")],
                 ["Date of appointment", "[ON REGISTRATION]"], ["Director ID", x.get("director_id", "[DIRECTOR ID]")]])
        d.p("Directorships I hold in other bodies corporate that are public companies, or subsidiaries of public companies (excluding related bodies corporate of the company): %s" % x.get("other_directorships", "[LIST, or write None]"))
        d.p("I declare that I am not disqualified from managing a corporation and that the information above is true and correct.")
        d.sig(full(x), "Director")
    d.note("Confirm the disclosure and declaration wording against the current Corporations Act 2001 (Cth) before use.")

    d.h1("3. APPLICATION FOR SHARES")
    for h in hs:
        d.h2(holder_name(h))
        d.p("[DD/MM/YYYY]")
        d.p("The Directors, %s, %s" % (co, office))
        d.p("I/We apply to be allotted shares in %s on the following terms:" % co)
        d.table([["Applicant name", holder_name(h)], ["ACN (if a company)", h.get("acn", "N/A")], ["Address", h.get("address", "[ADDRESS]")],
                 ["Number of shares", str(h.get("shares", "[NUMBER]"))],
                 ["Class of shares", "%s (%s)" % (c.d.get("share_class_code", "[CLASS]"), c.d.get("share_class_title", "[TITLE]"))],
                 ["Amount payable per share", c.d.get("price_per_share", "$[ISSUE PRICE]")],
                 ["Total amount payable", c.d.get("total_each", "$[TOTAL]")],
                 ["Amount to be paid on allotment", c.d.get("fully_paid", "[fully paid / partly paid]")]])
        d.p("I/We agree to be bound by the constitution of the company.")
        if h.get("type") == "company":
            d.sig(holder_name(h), "signed by %s, %s, for and on behalf of %s" % (h.get("signatory", "[SIGNATORY NAME]"), h.get("signatory_role", "[director]"), holder_name(h)))
            d.note("Confirm the signatory is authorised to sign for the company.")
        else:
            d.sig(holder_name(h), "applicant")

    d.h1("4. [RESERVED]")
    d.p("No company secretary is being appointed, so no consent to act as secretary is required.")

    d.h1("5. OCCUPIER\u2019S CONSENT TO REGISTERED OFFICE")
    d.p("[DD/MM/YYYY]")
    d.p("The Directors, %s, %s" % (co, office))
    d.p("Consent to use of address as registered office")
    d.p("%s is the occupier of the premises at the address below. I/we consent in writing to that address being used as the registered office of %s, and confirm that this consent has not been withdrawn." % (c.g("office_occupier", "OCCUPIER NAME"), co))
    d.table([["Address", office]])
    d.sig(c.g("office_occupier", "OCCUPIER NAME"), "occupier")
    d.note("Needed only where the company does not itself occupy the premises. If more than one person owns or occupies the premises, confirm whether each should sign.")
    return d


# ---------------------------------------------------------- post-registration pack
def post_registration(c):
    d = Doc("Post-Registration Pack: %s" % company(c))
    co, acn = company(c), c.g("acn", "ACN")
    ds, hs = directors(c), holders(c)
    d.h1("POST-REGISTRATION DOCUMENT PACK: %s" % co.upper())
    d.p("ACN %s. Complete after ASIC issues the ACN and certificate of registration." % acn)
    d.note("Have a lawyer or compliance team review before use. Dates of birth, Director IDs and any TFN are sensitive: store and share only through secure channels.")
    d.h1("1. FIRST DIRECTORS\u2019 RESOLUTION")
    d.p("Resolutions of the directors of %s, ACN %s, made on [DD/MM/YYYY], being the date of registration." % (co, acn))
    d.p("1. Registration and constitution: noted that the company was registered on [DD/MM/YYYY] and that the constitution was adopted on registration.")
    d.p("2. Directors: resolved that, each having consented to act, %s be confirmed as the first directors of the company." % "; ".join(full(x) for x in ds))
    d.p("3. Public officer: resolved that [PUBLIC OFFICER NAME], having consented to act, be appointed public officer of the company (delete if not required).")
    d.p("4. Members and shares: resolved that, each having agreed in writing to take up shares, the following be confirmed as the first members and the shares allotted effective [DD/MM/YYYY]:")
    d.table([[holder_name(h), c.d.get("share_class_code", "[CLASS]"), str(h.get("shares", "[NUMBER]")), c.d.get("price_per_share", "$[AMOUNT]")] for h in hs],
            ["Member", "Class", "Number of shares", "Paid per share"])
    d.p("5. Registered office: resolved that the registered office is %s from the date of registration." % c.g("registered_office", "ADDRESS"))
    d.p("6. Principal place of business: resolved that it is %s from the date of registration." % c.d.get("principal_place", "the same as the registered office"))
    d.p("7. Certificates and registers: resolved that share certificates be issued and the register of officers, register of members and share allotment journal be established and maintained.")
    for x in ds:
        d.sig(full(x), "Director")
    d.h1("2. PUBLIC OFFICER APPOINTMENT NOTICE AND CONSENT")
    d.note("Check current ATO requirements for whether a public officer is needed, who may be appointed, and when notice is due. The ATO form asks for a tax file number: highly sensitive.")
    d.table([["Name", "[FULL NAME]"], ["Date of birth", "[DD/MM/YYYY]"], ["Residential address", "[ADDRESS]"], ["Telephone", "[PHONE]"],
             ["Company", co], ["ACN", acn], ["Registered office", c.g("registered_office", "ADDRESS")]])
    d.p("I consent to act as public officer of the company.")
    d.sig("[PUBLIC OFFICER NAME]", "Public Officer")
    d.h1("3. SHARE CERTIFICATES")
    for n, h in enumerate(hs, 1):
        d.h2("Certificate no. %d" % n)
        d.p("%s, ACN %s. Incorporated in %s on [DD/MM/YYYY] under the Corporations Act 2001 (Cth). Registered office: %s." % (co, acn, c.g("state", "STATE"), c.g("registered_office", "ADDRESS")))
        d.p("This is to certify that %s of %s is the registered holder of %s %s shares in the company, subject to the constitution, with $[AMOUNT] paid per share." % (
            holder_name(h), h.get("address", "[ADDRESS]"), h.get("shares", "[NUMBER]"), c.d.get("share_class_code", "[CLASS]")))
        d.sig(full(ds[0]) if ds else "[DIRECTOR NAME]", "Director")
    d.h1("4. REGISTER OF OFFICERS")
    d.table([[full(x) + ", " + x.get("address", "[ADDRESS]"), x.get("dob", "[DD/MM/YYYY]"), x.get("pob", "[PLACE OF BIRTH]"), "Director", "[DD/MM/YYYY]", "", x.get("director_id", "[DIRECTOR ID]")] for x in ds],
            ["Full name and residential address", "Date of birth", "Place of birth", "Position", "Date appointed", "Date ceased", "Director ID"])
    d.h1("5. REGISTER OF MEMBERS")
    for h in hs:
        d.p("Member: %s. Address: %s. Share class: %s. Date of entry: [DD/MM/YYYY]." % (holder_name(h), h.get("address", "[ADDRESS]"), c.d.get("share_class_code", "[CLASS]")))
        d.table([["[DD/MM/YYYY]", "Subscription", str(h.get("shares", "[NUMBER]")), "", str(h.get("shares", "[NUMBER]")), "", c.d.get("price_per_share", "$[AMOUNT]"), "[CERT NO.]", c.d.get("price_per_share", "$[AMOUNT]")]],
                ["Date", "Transaction", "Acquired", "Transferred", "Balance", "To or from", "Consideration per share", "Certificate no.", "Paid per share"])
    d.h1("6. SHARE ALLOTMENT JOURNAL")
    d.table([["[DD/MM/YYYY]", "Subscription", holder_name(h) + ", " + h.get("address", "[ADDRESS]"), "[CERT NO.]", c.d.get("share_class_code", "[CLASS]"),
              str(h.get("shares", "[NUMBER]")), "[Cash / Other]"] for h in hs],
            ["Date entered", "Transaction", "Member name and address", "Certificate no.", "Class", "Number of shares", "Consideration"])
    return d



def strip_metadata(path):
    """Blank all document properties (title, author, dates, app stats, custom props), remove
    Word revision and document IDs and the preview-picture setting, and normalise zip
    timestamps so the .docx carries no metadata."""
    import re as _re
    import zipfile
    core = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
            'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
            'xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>')
    app = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
           '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
           'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"/>')
    tmp = path + ".tmp"
    with zipfile.ZipFile(path) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            name = item.filename
            if name in ("docProps/custom.xml", "docProps/thumbnail.jpeg", "docProps/thumbnail.png"):
                continue
            data = zin.read(name)
            if name == "docProps/core.xml":
                data = core.encode("utf-8")
            elif name == "docProps/app.xml":
                data = app.encode("utf-8")
            elif name == "[Content_Types].xml":
                data = _re.sub(rb"<Override[^>]*PartName=\"/docProps/(custom|thumbnail)[^>]*/>", b"", data)
            elif name == "_rels/.rels":
                data = _re.sub(rb"<Relationship [^>]*Target=\"docProps/(custom|thumbnail)[^>]*/>", b"", data)
            elif name == "word/settings.xml":
                data = _re.sub(rb"<(w:rsids|w:docVars)\b[^>]*?(?:/>|>.*?</\1>)", b"", data, flags=_re.S)
                data = _re.sub(rb"<(?:w:rsidRoot|w14:docId|w15:docId|w:savePreviewPicture)\b[^>]*/>", b"", data)
            if name.endswith(".xml"):
                data = _re.sub(rb'\s(?:w:rsid[A-Za-z]*|w14:paraId|w14:textId)="[^"]*"', b"", data)
            zi = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            zout.writestr(zi, data)
    os.replace(tmp, path)


def write(doc, outdir, name):
    os.makedirs(outdir, exist_ok=True)
    hp = os.path.join(outdir, name + ".html")
    dp = os.path.join(outdir, name + ".docx")
    with open(hp, "w", encoding="utf-8") as f:
        f.write(doc.html())
    subprocess.run(["pandoc", hp, "-f", "html", "-t", "docx", "-o", dp], check=True)
    try:
        import docx as pydocx
        m = pydocx.Document(dp)
        first = True
        for para in m.paragraphs:
            if para.style.name == "Heading 1":
                if not first:
                    para.paragraph_format.page_break_before = True
                first = False
        m.save(dp)
    except Exception as ex:  # formatting polish only
        print("post-process skipped:", ex)
    strip_metadata(dp)
    return hp, dp


def main():
    cfg = Cfg(json.load(open(sys.argv[1], encoding="utf-8")))
    out = sys.argv[2]
    slug = cfg.d.get("company_name", "Company").replace(" ", "_")
    outs = [write(constitution(cfg), out, "%s_Constitution_DRAFT" % slug),
            write(incorporation(cfg), out, "%s_Incorporation_Pack_DRAFT" % slug)]
    if "--post-registration" in sys.argv:
        outs.append(write(post_registration(cfg), out, "%s_Post_Registration_Pack_DRAFT" % slug))
    for o in outs:
        print(o[1])


if __name__ == "__main__":
    main()
